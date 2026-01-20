#!/bin/bash

# ============================================================================
# PROJECT:   Armbian PBX Installer (Asterisk 22 + FreePBX 17)
# TARGET:    Armbian 12 Bookworm (ARM64 - s905x3)
# VERSION:   1.0
# ============================================================================

# --- 1. CONFIGURATION ---
REPO_OWNER="slythel2"
REPO_NAME="FreePBX-17-for-Armbian-12-Bookworm"
FALLBACK_ARTIFACT="https://github.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/releases/download/1.0/asterisk-22-current-arm64-debian12-v2.tar.gz"

DB_ROOT_PASS="armbianpbx"
LOG_FILE="/var/log/pbx_install.log"
DEBIAN_FRONTEND=noninteractive

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"; exit 1; }

if [[ $EUID -ne 0 ]]; then echo "Run as root!"; exit 1; fi

# --- UPDATER ---
if [[ "$1" == "--update" ]]; then
    log "Starting Asterisk 22 Surgical Update..."
    
    if ! command -v asterisk &> /dev/null; then
        error "Asterisk is not installed. Run the full installer first."
    fi
    
    systemctl stop asterisk
    sleep 2
    pkill -9 asterisk 2>/dev/null
    
    # Artifact Detection
    log "Detecting latest release..."
    if ! command -v jq &> /dev/null; then apt-get update && apt-get install -y jq; fi
    LATEST_URL=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" | jq -r '.assets[] | select(.name | contains("asterisk")) | .browser_download_url' | head -n 1)
    [ -z "$LATEST_URL" ] && ASTERISK_ARTIFACT_URL="$FALLBACK_ARTIFACT" || ASTERISK_ARTIFACT_URL="$LATEST_URL"
    
    # Staging
    STAGE_DIR="/tmp/asterisk_update_stage"
    rm -rf "$STAGE_DIR" && mkdir -p "$STAGE_DIR"
    cd /tmp
    wget -q -O asterisk_update.tar.gz "$ASTERISK_ARTIFACT_URL"
    tar -xzf asterisk_update.tar.gz -C "$STAGE_DIR"

    # Copy Binaries and Modules only to preserve configs
    log "Deploying updated binaries and modules (Surgical)..."
    [ -d "$STAGE_DIR/usr/sbin" ] && cp -f "$STAGE_DIR/usr/sbin/asterisk" /usr/sbin/
    [ -d "$STAGE_DIR/usr/lib/asterisk/modules" ] && cp -rf "$STAGE_DIR/usr/lib/asterisk/modules"/* /usr/lib/asterisk/modules/
    [ -d "$STAGE_DIR/usr/include/asterisk" ] && cp -rf "$STAGE_DIR/usr/include/asterisk"/* /usr/include/asterisk/
    
    # Cleanup Stage
    rm -rf "$STAGE_DIR" asterisk_update.tar.gz
    
    log "Refreshing dynamic library cache..."
    ldconfig
    
    # Permission sync for new modules
    chown -R root:root /usr/lib/asterisk/modules
    chmod -R 755 /usr/lib/asterisk/modules
    
    log "Restarting services..."
    systemctl start asterisk
    
    # Readiness Check (AMI 5038)
    AMI_OK=0
    for i in {1..30}; do
        if timeout 1 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/5038' 2>/dev/null; then
            AMI_OK=1
            break
        fi
        sleep 1
    done
    
    if [ $AMI_OK -eq 1 ]; then
        log "Asterisk AMI is responding. Reloading FreePBX..."
        fwconsole chown
        fwconsole reload
        log "Update completed successfully."
        exit 0
    else
        error "Asterisk started but AMI (Port 5038) is unreachable. Check /etc/asterisk/manager.conf"
    fi
fi

# --- 2. MAIN INSTALLER ---
clear
echo "========================================================"
echo "   ARMBIAN 12 FREEPBX 17 INSTALLER (Asterisk 22 LTS)    "
echo "========================================================"

log "Preparing system environment..."
apt-get update --allow-releaseinfo-change
apt-get upgrade -y

# Dependencies
apt-get install -y \
    git curl wget vim htop subversion sox pkg-config sngrep \
    apache2 mariadb-server mariadb-client odbc-mariadb \
    libxml2 libsqlite3-0 libjansson4 libedit2 libxslt1.1 \
    libopus0 libvorbis0a libspeex1 libspeexdsp1 libgsm1 \
    unixodbc unixodbc-dev odbcinst libltdl7 libicu-dev \
    liburiparser1 libjwt-dev liblua5.4-0 libtinfo6 \
    libsrtp2-1 libportaudio2 nodejs npm acl haveged jq \
    || error "Dependency installation failed."

npm install -g pm2@latest
pm2 set pm2:max_memory_restart 512M

# --- 3. PHP 8.2 CONFIGURATION ---
log "Configuring PHP 8.2 stack..."
apt-get install -y php php-cli php-common php-curl php-gd php-mbstring \
    php-mysql php-soap php-xml php-intl php-zip php-bcmath \
    php-ldap php-pear libapache2-mod-php

PHP_INI_PATHS=("/etc/php/8.2/apache2/php.ini" "/etc/php/8.2/cli/php.ini")
for INI in "${PHP_INI_PATHS[@]}"; do
    if [ -f "$INI" ]; then
        sed -i 's/^;*memory_limit = .*/memory_limit = 512M/' "$INI"
        sed -i 's/^;*upload_max_filesize = .*/upload_max_filesize = 120M/' "$INI"
        sed -i 's/^;*post_max_size = .*/post_max_size = 120M/' "$INI"
        sed -i 's/^;*max_execution_time = .*/max_execution_time = 600/' "$INI"
    fi
done

# --- 4. ASTERISK INSTALLATION ---
log "Deploying Asterisk 22 artifacts..."
getent group asterisk >/dev/null || groupadd asterisk
if ! getent passwd asterisk >/dev/null; then
    useradd -r -d /var/lib/asterisk -s /bin/bash -g asterisk asterisk
    usermod -aG audio,dialout,www-data asterisk
fi

cd /tmp
wget -q -O asterisk.tar.gz "$FALLBACK_ARTIFACT"
tar -xzf asterisk.tar.gz -C /
rm asterisk.tar.gz

ldconfig

mkdir -p /var/run/asterisk /var/log/asterisk /var/lib/asterisk /var/spool/asterisk /etc/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/log/asterisk /var/lib/asterisk /var/spool/asterisk /etc/asterisk
chown -R root:root /usr/lib/asterisk/modules
chmod -R 755 /usr/lib/asterisk/modules

# Systemd Service
cat > /etc/systemd/system/asterisk.service <<'EOF'
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

# --- 5. DATABASE SETUP ---
log "Initializing MariaDB..."
systemctl start mariadb

if mysqladmin -u root ping &>/dev/null; then
    mysqladmin -u root password "$DB_ROOT_PASS" 2>/dev/null
fi

if [ ! -f /etc/mysql/conf.d/freepbx.cnf ]; then
cat > /etc/mysql/conf.d/freepbx.cnf <<'EOF'
[mysqld]
sql_mode = ""
innodb_strict_mode = 0
performance_schema = OFF
innodb_buffer_pool_size = 128M
EOF
    systemctl restart mariadb
fi

# Provision Databases
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asterisk; CREATE DATABASE IF NOT EXISTS asteriskcdrdb;"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asterisk.* TO 'asterisk'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'localhost';"
mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# --- 6. APACHE & FREEPBX ---
log "Configuring Apache..."
sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
a2enmod rewrite && a2dissite 000-default.conf 2>/dev/null
rm -f /var/www/html/index.html
systemctl restart apache2

log "Installing FreePBX 17..."
cd /usr/src
wget -q http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz
tar xfz freepbx-17.0-latest.tgz
cd freepbx
./install -n --dbuser asterisk --dbpass "$DB_ROOT_PASS" --webroot /var/www/html --user asterisk --group asterisk

# --- 7. ODBC & PERSISTENCE ---

REAL_SOCKET=$(find /run /var/run -name mysqld.sock 2>/dev/null | head -n 1)
ODBC_DRIVER=$(find /usr/lib -name "libmaodbc.so" | head -n 1)

# ODBC Configuration
if [ -n "$ODBC_DRIVER" ]; then
cat > /etc/odbcinst.ini <<EOF
[MariaDB]
Description=ODBC for MariaDB
Driver=$ODBC_DRIVER
Setup=$ODBC_DRIVER
UsageCount=1
EOF

cat > /etc/odbc.ini <<EOF
[MySQL-asteriskcdrdb]
Description=MySQL connection to 'asteriskcdrdb' database
Driver=MariaDB
Server=localhost
Database=asteriskcdrdb
Port=3306
Socket=$REAL_SOCKET
Option=3
EOF
fi

# Permission Fix Script
cat > /usr/local/bin/fix_free_perm.sh <<'EOF'
#!/bin/bash
DYN_SOCKET=$(find /run /var/run -name mysqld.sock 2>/dev/null | head -n 1)
[ -n "$DYN_SOCKET" ] && ln -sf "$DYN_SOCKET" /tmp/mysql.sock
mkdir -p /var/run/asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/log/asterisk /var/lib/asterisk /etc/asterisk
if [ -x /usr/sbin/fwconsole ]; then
    /usr/sbin/fwconsole chown &>/dev/null
fi
exit 0
EOF
chmod +x /usr/local/bin/fix_free_perm.sh

# Permission Fix Service
cat > /etc/systemd/system/free-perm-fix.service <<'EOF'
[Unit]
Description=FreePBX Permission Fix
After=asterisk.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/fix_free_perm.sh
[Install]
WantedBy=multi-user.target
EOF
systemctl enable free-perm-fix.service

# --- 8. STATUS BANNER ---
cat > /etc/update-motd.d/99-pbx-status <<'EOF'
#!/bin/bash
BLUE='\033[0;34m'
NC='\033[0m'
IP_ADDR=$(hostname -I | cut -d' ' -f1)
echo -e "${BLUE}================================================================${NC}"
echo -e "   ARMBIAN PBX - ASTERISK 22 LTS + FREEPBX 17"
echo -e "   Web GUI: http://$IP_ADDR/admin"
echo -e "${BLUE}================================================================${NC}"
EOF
chmod +x /etc/update-motd.d/99-pbx-status
rm -f /etc/motd

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}            FREEPBX INSTALLATION COMPLETE!              ${NC}"
echo -e "${GREEN}   Access: http://$(hostname -I | cut -d' ' -f1)/admin  ${NC}"
echo -e "${GREEN}========================================================${NC}"
