#!/bin/bash

# ============================================================================
# PROJECT:   Armbian PBX Installer v0.9.6
# TARGET:    Debian 12 (Bookworm) / S905X3
# STACK:     Asterisk 21 + FreePBX 17 + PHP 8.2
# ============================================================================

# --- 1. CONFIGURATION ---
ASTERISK_ARTIFACT_URL="https://github.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/releases/download/1.0/asterisk-21.12.0-arm64-debian12-v2.tar.gz"
DB_ROOT_PASS="armbianpbx"
LOG_FILE="/var/log/pbx_install.log"
DEBIAN_FRONTEND=noninteractive

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"; exit 1; }

if [[ $EUID -ne 0 ]]; then echo "Run as root!"; exit 1; fi

clear
echo "========================================================"
echo "   ARMBIAN PBX INSTALLER (S905X3 Optimized)             "
echo "========================================================"
sleep 3

# --- 2. SYSTEM PREPARATION ---
log "Updating system..."
apt-get update --allow-releaseinfo-change
apt-get upgrade -y

log "Installing dependencies..."
apt-get install -y \
    git curl wget vim htop subversion sox pkg-config sngrep \
    apache2 mariadb-server mariadb-client odbc-mariadb \
    libxml2 libsqlite3-0 libjansson4 libedit2 libxslt1.1 \
    libopus0 libvorbis0a libspeex1 libspeexdsp1 libgsm1 \
    unixodbc unixodbc-dev odbcinst libltdl7 libicu-dev \
    nodejs npm acl haveged \
    || error "Base package installation failed"

# PM2 & Memory Limits (S905X3)
npm install -g pm2@latest
pm2 set pm2:max_memory_restart 512M

# --- 3. PHP 8.2 CONFIGURATION ---
log "Installing PHP 8.2..."
apt-get install -y \
    php php-cli php-common php-curl php-gd php-mbstring \
    php-mysql php-soap php-xml php-intl php-zip php-bcmath \
    php-ldap php-pear libapache2-mod-php

# PHP Optimization
sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/apache2/php.ini
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 120M/' /etc/php/8.2/apache2/php.ini
sed -i 's/post_max_size = .*/post_max_size = 120M/' /etc/php/8.2/apache2/php.ini
sed -i 's/max_execution_time = .*/max_execution_time = 600/' /etc/php/8.2/apache2/php.ini

# --- 4. ASTERISK USER & ARTIFACT ---
log "Configuring Asterisk user..."
if ! getent group asterisk >/dev/null; then groupadd asterisk; fi
if ! getent passwd asterisk >/dev/null; then
    useradd -r -d /var/lib/asterisk -s /bin/bash -g asterisk asterisk
    usermod -aG audio,dialout,www-data asterisk
fi

log "Downloading and installing Asterisk artifact..."
cd /tmp
wget -O asterisk.tar.gz "$ASTERISK_ARTIFACT_URL"
tar -xzvf asterisk.tar.gz -C /
rm asterisk.tar.gz

# Library Fix
echo "/usr/lib" > /etc/ld.so.conf.d/asterisk.conf
ldconfig

# Permissions and Directories
mkdir -p /var/run/asterisk /var/log/asterisk /var/lib/asterisk /var/spool/asterisk /etc/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /etc/asterisk /usr/lib/asterisk

# Creating Systemd Service
cat <<EOF > /etc/systemd/system/asterisk.service
[Unit]
Description=Asterisk PBX
Wants=network.target network-online.target
After=network.target network-online.target mariadb.service

[Service]
Type=simple
User=asterisk
Group=asterisk
ExecStart=/usr/sbin/asterisk -f -C /etc/asterisk/asterisk.conf
ExecStop=/usr/sbin/asterisk -rx 'core stop now'
ExecReload=/usr/sbin/asterisk -rx 'core reload'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable asterisk mariadb apache2

# --- 5. STARTING CORE SERVICES (CRITICAL ORDER) ---
log "Starting core services before FreePBX installation..."
systemctl start mariadb
# Waiting for MariaDB socket...
until mysqladmin ping &>/dev/null; do sleep 1; done

# MariaDB Optimization
if [ ! -f /etc/mysql/conf.d/freepbx.cnf ]; then
    cat <<EOF > /etc/mysql/conf.d/freepbx.cnf
[mysqld]
sql_mode = ""
innodb_strict_mode = 0
performance_schema = OFF
innodb_buffer_pool_size = 128M
EOF
    systemctl restart mariadb
    sleep 2
fi

# START ASTERISK NOW (Necessary for FreePBX installer success)
log "Starting Asterisk..."
systemctl start asterisk
sleep 3

# --- 6. DB & APACHE CONFIGURATION ---
log "Configuring Apache..."
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
echo "ServerName localhost" >> /etc/apache2/apache2.conf
a2enmod rewrite
systemctl restart apache2

mysqladmin -u root password "$DB_ROOT_PASS" 2>/dev/null || true

# ODBC Driver Fix
ODBC_DRIVER=$(find /usr/lib -name "libmaodbc.so" | head -n 1)
if [ ! -z "$ODBC_DRIVER" ]; then
    cat <<EOF > /etc/odbcinst.ini
[MariaDB]
Description=ODBC for MariaDB
Driver=$ODBC_DRIVER
Setup=$ODBC_DRIVER
UsageCount=1
EOF
    cat <<EOF > /etc/odbc.ini
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
Driver=MariaDB
Server=localhost
Database=asteriskcdrdb
Port=3306
Socket=/var/run/mysqld/mysqld.sock
Option=3
EOF
fi

# Creating Databases
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asterisk;"
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asteriskcdrdb;"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asterisk.* TO 'asterisk'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'localhost';"
mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# --- 7. FREEPBX INSTALLATION ---
log "Downloading FreePBX..."
cd /usr/src
rm -rf freepbx*
wget http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz
tar xfz freepbx-17.0-latest.tgz
cd freepbx

log "Running FreePBX Installer..."
# Now that Asterisk is active, core file extraction should not fail
./install -n \
    --dbuser asterisk \
    --dbpass "$DB_ROOT_PASS" \
    --webroot /var/www/html \
    --user asterisk \
    --group asterisk

# --- 8. PHP 8.2 PATCHES (FOR CSS RENDERING) ---
log "Applying PHP 8.2 Patches..."
LESS_FILE="/var/www/html/admin/libraries/less/Less.php"
CACHE_FILE="/var/www/html/admin/libraries/less/Cache.php"

if [ -f "$LESS_FILE" ]; then
    sed -i 's/array_merge(\$this->rules, \$this->GetRules(\$file_path))/array_merge(\$this->rules, (array)\$this->GetRules(\$file_path))/' "$LESS_FILE"
    sed -i 's/\$this->GetCachedVariable(\$import))/(array)\$this->GetCachedVariable(\$import))/' "$LESS_FILE"
fi

if [ -f "$CACHE_FILE" ]; then
    sed -i "s/return \$value;/return (array)\$value;/" "$CACHE_FILE"
fi

# --- 9. FINALIZATION & PERMISSIONS ---
log "Applying Permissions..."
chown -R asterisk:asterisk /var/www/html
rm -f /var/www/html/index.html

log "Cleaning problematic modules..."
fwconsole ma remove sysadmin 2>/dev/null
fwconsole ma remove firewall 2>/dev/null
fwconsole ma disable dashboard
fwconsole ma disable ucp

# Re-run chown via fwconsole for safety
fwconsole chown

# --- 10. REBOOT PROOFING ---
cat > /usr/local/bin/fix_free_perm.sh << EOF
#!/bin/bash
mkdir -p /var/run/asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/log/asterisk
ln -sf /var/run/mysqld/mysqld.sock /tmp/mysql.sock
fwconsole chown &>/dev/null
rm -rf /var/www/html/admin/assets/less/cache/*
exit 0
EOF
chmod +x /usr/local/bin/fix_free_perm.sh

cat > /etc/systemd/system/free-perm-fix.service << EOF
[Unit]
Description=FreePBX Perm Fix
Requires=asterisk.service
After=asterisk.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix_free_perm.sh
[Install]
WantedBy=multi-user.target
EOF
systemctl enable free-perm-fix.service

# --- 11. STATUS BANNER ---
log "Generating SSH Banner..."
cat << 'EOF' > /etc/update-motd.d/99-pbx-status
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
IP_ADDR=$(hostname -I | cut -d' ' -f1)
check_service() {
    systemctl is-active --quiet $1 && echo -e "${GREEN}ONLINE${NC}" || echo -e "${RED}OFFLINE${NC}"
}
echo -e "${BLUE}================================================================${NC}"
echo -e "   ARMBIAN PBX - ASTERISK 21 + FREEPBX 17 (ARM64)"
echo -e "${BLUE}================================================================${NC}"
echo -e " IP Address:   ${YELLOW}$IP_ADDR${NC}"
echo -e " Web GUI:      ${YELLOW}http://$IP_ADDR/admin${NC}"
echo -e " Asterisk:     $(check_service asterisk)"
echo -e " MariaDB:      $(check_service mariadb)"
echo -e " Apache Web:   $(check_service apache2)"
echo -e "${BLUE}================================================================${NC}"
EOF
chmod +x /etc/update-motd.d/99-pbx-status
rm -f /etc/motd

# --- 12. FINAL RELOAD ---
log "Final reload..."
fwconsole reload

echo "========================================================"
echo "   COMPLETED! Access: http://$(hostname -I | cut -d' ' -f1)/admin"
echo "========================================================"
