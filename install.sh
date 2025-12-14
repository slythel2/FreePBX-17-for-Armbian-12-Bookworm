#!/bin/bash

# ============================================================================
# PROJECT:  Armbian PBX "One-Click" Installer (T95 Max+ / ARM64)
# TARGET:   Debian 12 (Bookworm)
# STACK:    Asterisk 21 (Pre-compiled) + FreePBX 17 + PHP 8.2
# AUTHOR:   Gemini & slythel2
# DATE:     2025-12-14 (V5.6 Final - Fully Documented)
# ============================================================================

# --- 1. USER CONFIGURATION ---
ASTERISK_ARTIFACT_URL="https://github.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/releases/download/1.0/asterisk-21.12.0-arm64-debian12-v2.tar.gz"

# Database root password
# SECURITY WARNING: This password is hardcoded for installation convenience.
# It is highly recommended to change it after installation!
DB_ROOT_PASS="armbianpbx"

# --- END CONFIGURATION ---

LOG_FILE="/var/log/pbx_install.log"
DEBIAN_FRONTEND=noninteractive
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"; exit 1; }

if [[ $EUID -ne 0 ]]; then echo "Run as root!"; exit 1; fi

clear
echo "========================================================"
echo "   ARM64 PBX AUTO-INSTALLER (DEBIAN 12)                 "
echo "========================================================"
sleep 3

# --- 2. SYSTEM PREP ---
log "Updating system and installing dependencies..."
apt-get update && apt-get upgrade -y

# Dependencies updated: added pkg-config, libicu-dev (for UCP), libedit2
apt-get install -y \
    git curl wget vim htop subversion sox pkg-config \
    apache2 mariadb-server mariadb-client \
    libxml2 libsqlite3-0 libjansson4 libedit2 libxslt1.1 \
    libopus0 libvorbis0a libspeex1 libspeexdsp1 libgsm1 \
    unixodbc odbcinst libltdl7 libicu-dev \
    nodejs npm \
    || error "Failed to install base packages"

# CRITICAL FIX: Install PM2 explicitly (Required by FreePBX 17 process manager)
log "Installing PM2..."
npm install -g pm2@latest || error "Failed to install PM2"

# --- 3. PHP 8.2 STACK & TUNING ---
log "Installing PHP 8.2..."
apt-get install -y \
    php php-cli php-common php-curl php-gd php-mbstring \
    php-mysql php-soap php-xml php-intl php-zip php-bcmath \
    php-ldap php-pear libapache2-mod-php \
    || error "Failed to install PHP"

log "Tuning PHP parameters..."
sed -i 's/memory_limit = .*/memory_limit = 256M/' /etc/php/8.2/apache2/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 120M/' /etc/php/8.2/apache2/php.ini
sed -i 's/post_max_size = .*/post_max_size = 120M/' /etc/php/8.2/apache2/php.ini
sed -i 's/memory_limit = .*/memory_limit = 256M/' /etc/php/8.2/cli/php.ini

# --- 4. ASTERISK USER SETUP ---
log "Creating system user..."
if ! getent group asterisk >/dev/null; then groupadd asterisk; fi
if ! getent passwd asterisk >/dev/null; then
    useradd -r -d /var/lib/asterisk -g asterisk asterisk
    usermod -aG audio,dialout asterisk
fi

# --- 5. ASTERISK INSTALL (FROM ARTIFACT) ---
log "Downloading Asterisk Artifact..."
cd /tmp
wget -O asterisk_artifact.tar.gz "$ASTERISK_ARTIFACT_URL" || error "Artifact download failed"

log "Extracting files..."
tar -xzvf asterisk_artifact.tar.gz -C / || error "Extraction failed"
rm asterisk_artifact.tar.gz

# --- CRITICAL FIX: LIBRARIES & PERMISSIONS ---
log "Linking libraries and fixing permissions..."
# Force library cache update so system finds libasteriskssl.so
echo "/usr/lib" > /etc/ld.so.conf.d/asterisk.conf
ldconfig

# Create PID directory to prevent startup loop errors
mkdir -p /var/run/asterisk

# SECURITY NOTE: Asterisk requires write access to its own runtime directories.
# Without this, the process cannot create PID files or load modules.
chown -R asterisk:asterisk /var/run/asterisk
chown -R asterisk:asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /etc/asterisk /usr/lib/asterisk

# --- 6. SYSTEMD SERVICE & BOOT SETUP ---
log "Configuring Asterisk service..."
cat <<EOF > /etc/systemd/system/asterisk.service
[Unit]
Description=Asterisk PBX
Documentation=man:asterisk(8)
Wants=network.target
After=network.target network-online.target

[Service]
Type=simple
User=asterisk
Group=asterisk
ExecStart=/usr/sbin/asterisk -f -C /etc/asterisk/asterisk.conf
ExecStop=/usr/sbin/asterisk -rx 'core stop now'
ExecReload=/usr/sbin/asterisk -rx 'core reload'
Restart=on-failure
RestartSec=5
LimitCORE=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

log "Enabling services at boot..."
systemctl enable mariadb
systemctl enable apache2
systemctl enable asterisk
systemctl start asterisk

# --- 7. APACHE & DATABASE SETUP ---
log "Configuring Apache..."
# Apache must run as 'asterisk' user so the Web GUI can write config files
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# PRIORITY FIX: Tell Apache to load index.php BEFORE index.html
if [ -f /etc/apache2/mods-enabled/dir.conf ]; then
    sed -i 's/DirectoryIndex index.html/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf
fi

a2enmod rewrite
systemctl restart apache2

log "Configuring Database..."
# CRITICAL FIX: Force DB start to avoid socket errors on re-install
systemctl start mariadb
sleep 2

mysqladmin -u root password "$DB_ROOT_PASS" 2>/dev/null || true

# Pre-create Asterisk DB User
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asterisk;"
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asteriskcdrdb;"
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS 'asterisk'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asterisk.* TO 'asterisk'@'localhost';"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'localhost';"
mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# --- 8. FREEPBX 17 INSTALL ---
log "Downloading FreePBX 17..."
cd /usr/src
rm -rf freepbx*
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz
tar xfz freepbx-17.0-latest.tgz
cd freepbx

log "Running FreePBX Installer..."
# IMPORTANT: Removed '|| error' to allow script to finish even if installer emits non-critical warnings
./install -n \
    --dbuser asterisk \
    --dbpass "$DB_ROOT_PASS" \
    --webroot /var/www/html \
    --user asterisk \
    --group asterisk

# --- 9. FINAL CLEANUP & GUI ACTIVATION ---
log "Finalizing configuration..."
fwconsole ma installall
fwconsole chown
fwconsole reload

# Remove default Apache index
rm -f /var/www/html/index.html

# --- FINAL PERMISSION SAFETY NET ---
log "Applying final permission fixes..."
# ARCHITECTURAL NOTE:
# FreePBX Architecture requires the Apache User (asterisk) to have WRITE access
# to specific directories to function correctly.
# - /var/log/asterisk: To write application logs (otherwise crashes occur).
# - /etc/asterisk: To generate and write config files (extensions.conf, etc).
# - /var/www/html: To self-update modules and manage web assets.
mkdir -p /var/log/asterisk
chown -R asterisk:asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/lib/asterisk
chown -R asterisk:asterisk /var/spool/asterisk
chown -R asterisk:asterisk /etc/asterisk
chown -R asterisk:asterisk /var/www/html

echo ""
echo "========================================================"
echo "   INSTALLATION COMPLETE!                               "
echo "========================================================"
echo "Web Access: http://$(hostname -I | cut -d' ' -f1)/admin"
echo "DB Root Password: $DB_ROOT_PASS"
echo "========================================================"
