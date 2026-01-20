#!/bin/bash

# ============================================================================
# PROJECT:   Armbian PBX Installer v1.0
# TARGET:    Debian 12 (Bookworm)
# STACK:     Asterisk 22 LTS + FreePBX 17 + LAMP
# REPO:      https://github.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm
# ============================================================================

# --- 1. CONFIGURATION ---
REPO_OWNER="slythel2"
REPO_NAME="FreePBX-17-for-Armbian-12-Bookworm"

# Fallback URL
FALLBACK_ARTIFACT="https://github.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/releases/download/1.0/asterisk-22-current-arm64-debian12-v2.tar.gz"

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

# --- UPDATER - Installs the latest Asterisk 22 ARM Compiled artifacts from the Repo ---
if [[ "$1" == "--update" ]]; then
    echo "========================================================"
    echo "   ASTERISK 22 LTS UPDATER                              "
    echo "========================================================"
    log "Starting update process..."
    
    if ! command -v asterisk &> /dev/null; then
        error "Asterisk is not installed. Run install.sh without arguments first."
    fi
    
    log "Stopping Asterisk..."
    systemctl stop asterisk
    sleep 2
    killall -9 asterisk 2>/dev/null
    
    log "Detecting latest Asterisk artifact..."
    if ! command -v jq &> /dev/null; then
        apt-get update && apt-get install -y jq
    fi

    LATEST_URL=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" \
        | grep "browser_download_url" \
        | grep "asterisk" \
        | head -n 1 \
        | cut -d '"' -f 4)

    if [ -z "$LATEST_URL" ]; then
        warn "Auto-detection failed. Using fallback URL."
        ASTERISK_ARTIFACT_URL="$FALLBACK_ARTIFACT"
    else
        ASTERISK_ARTIFACT_URL="$LATEST_URL"
        log "Artifact found: $(basename $ASTERISK_ARTIFACT_URL)"
    fi
    
    log "Downloading update..."
    cd /tmp
    wget -O asterisk_update.tar.gz "$ASTERISK_ARTIFACT_URL" || error "Download failed."
    
    log "Installing update..."
    tar -xzvf asterisk_update.tar.gz -C /
    rm asterisk_update.tar.gz
    
    chown -R asterisk:asterisk /usr/lib/asterisk /var/lib/asterisk
    
    log "Restarting Asterisk..."
    systemctl start asterisk
    
    log "Waiting for Asterisk to initialize..."
    for i in {1..30}; do
        if asterisk -rx "core waitfullybooted" &>/dev/null; then
            break
        fi
        sleep 1
    done
    
    if systemctl is-active --quiet asterisk; then
        log "Asterisk updated successfully."
        exit 0
    else
        error "Asterisk failed to start after update. Check logs."
    fi
fi

clear
echo "========================================================"
echo "   ARMBIAN PBX INSTALLER v1.0 (Asterisk 22 LTS)         "
echo "========================================================"
sleep 2

# --- 2. SYSTEM PREPARATION ---
log "Updating system..."
apt-get update --allow-releaseinfo-change
apt-get upgrade -y

log "Installing base dependencies..."
apt-get install -y \
    git curl wget vim htop subversion sox pkg-config sngrep \
    apache2 mariadb-server mariadb-client odbc-mariadb \
    libxml2 libsqlite3-0 libjansson4 libedit2 libxslt1.1 \
    libopus0 libvorbis0a libspeex1 libspeexdsp1 libgsm1 \
    unixodbc unixodbc-dev odbcinst libltdl7 libicu-dev \
    liburiparser1 libjwt0 liblua5.4-0 libtinfo6 \
    libsrtp2-1 libportaudio2 libsqlite3-0 \
    nodejs npm acl haveged jq \
    || error "Base package installation failed"

# PM2 & Memory Limits --- You can change the 512M value if you have a machine with more memory than 4GB ---
npm install -g pm2@latest
pm2 set pm2:max_memory_restart 512M

# --- 3. PHP 8.2 CONFIGURATION ---
log "Installing PHP 8.2..."
apt-get install -y \
    php php-cli php-common php-curl php-gd php-mbstring \
    php-mysql php-soap php-xml php-intl php-zip php-bcmath \
    php-ldap php-pear libapache2-mod-php

# PHP Optimization
PHP_INI="/etc/php/8.2/apache2/php.ini"
log "Tuning PHP configuration in $PHP_INI..."
sed -i 's/^;*memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
sed -i 's/^;*upload_max_filesize = .*/upload_max_filesize = 120M/' "$PHP_INI"
sed -i 's/^;*post_max_size = .*/post_max_size = 120M/' "$PHP_INI"
sed -i 's/^;*max_execution_time = .*/max_execution_time = 600/' "$PHP_INI"
sed -i 's/^;*max_input_vars = .*/max_input_vars = 5000/' "$PHP_INI"

# Verification Step
grep -E "^(memory_limit|upload_max_filesize|post_max_size|max_execution_time|max_input_vars)" "$PHP_INI" | tee -a "$LOG_FILE"

# --- 4. ASTERISK ARTIFACT DETECTION ---
log "Detecting latest Asterisk artifact from GitHub..."
LATEST_URL=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" \
    | grep "browser_download_url" \
    | grep "asterisk" \
    | head -n 1 \
    | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    warn "Auto-detection failed. Using fallback URL."
    ASTERISK_ARTIFACT_URL="$FALLBACK_ARTIFACT"
else
    ASTERISK_ARTIFACT_URL="$LATEST_URL"
    log "Artifact found: $(basename $ASTERISK_ARTIFACT_URL)"
fi

# --- 5. ASTERISK USER & INSTALL ---
log "Configuring Asterisk user..."
if ! getent group asterisk >/dev/null; then groupadd asterisk; fi
if ! getent passwd asterisk >/dev/null; then
    useradd -r -d /var/lib/asterisk -s /bin/bash -g asterisk asterisk
    usermod -aG audio,dialout,www-data asterisk
fi

log "Downloading and deploying Asterisk..."
cd /tmp
wget -O asterisk.tar.gz "$ASTERISK_ARTIFACT_URL" || error "Download failed."
tar -xzvf asterisk.tar.gz -C /
rm asterisk.tar.gz

# Shared Library Fix
echo "/usr/lib" > /etc/ld.so.conf.d/asterisk.conf
ldconfig

# Directory Permissions
mkdir -p /var/run/asterisk /var/log/asterisk /var/lib/asterisk /var/spool/asterisk /etc/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /etc/asterisk /usr/lib/asterisk

# Systemd Service Creation
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

# --- 6. STARTING CORE SERVICES ---
log "Starting Database..."
# Force MariaDB cleanup if it fails to start initially
if ! systemctl start mariadb; then
    warn "MariaDB failed to start. Attempting repair..."
    systemctl stop mariadb
    rm -rf /var/lib/mysql/ib_logfile*
    # Try initializing if directory is empty
    if [ -z "$(ls -A /var/lib/mysql)" ]; then
       mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    fi
    systemctl start mariadb || error "MariaDB dead. Check logs."
fi

# Checks actual connectivity
log "Waiting for MariaDB connectivity..."
DB_READY=0
for i in {1..30}; do
    if mysqladmin ping &>/dev/null; then
        DB_READY=1
        log "MariaDB is online and responding."
        break
    fi
    sleep 1
done

if [ $DB_READY -eq 0 ]; then
    warn "MariaDB service is up but not responding to ping. Attempting to proceed anyway..."
fi

# Locates and Link Socket
REAL_SOCKET=$(find /run /var/run -name mysqld.sock 2>/dev/null | head -n 1)
if [ -n "$REAL_SOCKET" ]; then
    log "Linking socket from $REAL_SOCKET..."
    mkdir -p /var/run/mysqld
    ln -sf "$REAL_SOCKET" /var/run/mysqld/mysqld.sock
    ln -sf "$REAL_SOCKET" /tmp/mysql.sock
else
    error "Could not find mysqld.sock! Database installation will fail."
fi

# MariaDB Tuning
if [ ! -f /etc/mysql/conf.d/freepbx.cnf ]; then
    cat <<EOF > /etc/mysql/conf.d/freepbx.cnf
[mysqld]
sql_mode = ""
innodb_strict_mode = 0
performance_schema = OFF
innodb_buffer_pool_size = 128M
EOF
    systemctl restart mariadb
    sleep 3
fi

log "Starting Asterisk..."
systemctl start asterisk
sleep 2

# --- 7. DB & APACHE CONFIGURATION ---
log "Configuring Apache..."
# Makes FreePBX index.php loads first
if [ -f /etc/apache2/mods-enabled/dir.conf ]; then
    sed -i 's/DirectoryIndex index.html/DirectoryIndex index.php index.html/' /etc/apache2/mods-enabled/dir.conf
fi

sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf
sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
if ! grep -q "ServerName localhost" /etc/apache2/apache2.conf; then
    echo "ServerName localhost" >> /etc/apache2/apache2.conf
fi

a2enmod rewrite
# Disables default site to prevent conflict
a2dissite 000-default.conf 2>/dev/null
# Nukes default index.html BEFORE installing FreePBX
rm -f /var/www/html/index.html

systemctl restart apache2

mysqladmin -u root password "$DB_ROOT_PASS" 2>/dev/null || true

# ODBC Setup
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
Socket=$REAL_SOCKET
Option=3
EOF
fi

# Databases Creation
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asterisk;"
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS asteriskcdrdb;"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asterisk.* TO 'asterisk'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO 'asterisk'@'localhost';"
mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# --- 8. FREEPBX INSTALLATION ---
log "Installing FreePBX 17..."
cd /usr/src
rm -rf freepbx*
wget -q http://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz
tar xfz freepbx-17.0-latest.tgz
cd freepbx

./install -n \
    --dbuser asterisk \
    --dbpass "$DB_ROOT_PASS" \
    --webroot /var/www/html \
    --user asterisk \
    --group asterisk

# --- 9. PHP 8.2 PATCHES ---
log "Applying PHP 8.2 patches..."
LESS_FILE="/var/www/html/admin/libraries/less/Less.php"
CACHE_FILE="/var/www/html/admin/libraries/less/Cache.php"

if [ -f "$LESS_FILE" ]; then
    sed -i 's/array_merge(\$this->rules, \$this->GetRules(\$file_path))/array_merge(\$this->rules, (array)\$this->GetRules(\$file_path))/' "$LESS_FILE"
    sed -i 's/\$this->GetCachedVariable(\$import))/(array)\$this->GetCachedVariable(\$import))/' "$LESS_FILE"
fi

if [ -f "$CACHE_FILE" ]; then
    sed -i "s/return \$value;/return (array)\$value;/" "$CACHE_FILE"
fi

# --- 10. FINALIZATION ---
log "Cleaning modules and setting permissions..."
if command -v fwconsole &> /dev/null; then
    fwconsole ma remove sysadmin 2>/dev/null
    fwconsole ma remove firewall 2>/dev/null
    fwconsole ma disable sms 2>/dev/null
    fwconsole ma disable ucp 2>/dev/null
    fwconsole chown
    fwconsole reload
else
    warn "fwconsole not found. FreePBX installation might have failed. Re-run manually."
fi

log " -- sysadmin and firewall Modules are proprietaries and cannot be used in this ARM configuration, for now -- "

# Permission fix
cat > /usr/local/bin/fix_free_perm.sh << EOF
#!/bin/bash
mkdir -p /var/run/asterisk /var/log/asterisk
chown -R asterisk:asterisk /var/run/asterisk /var/log/asterisk
ln -sf $REAL_SOCKET /tmp/mysql.sock
if command -v fwconsole &> /dev/null; then
    fwconsole chown &>/dev/null
fi
exit 0
EOF
chmod +x /usr/local/bin/fix_free_perm.sh

cat > /etc/systemd/system/free-perm-fix.service << EOF
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

# --- 11. SSH STATUS BANNER ---
cat << 'EOF' > /etc/update-motd.d/99-pbx-status
#!/bin/bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
IP_ADDR=$(hostname -I | cut -d' ' -f1)
check_service() {
    systemctl is-active --quiet $1 && echo -e "${GREEN}ONLINE${NC}" || echo -e "${RED}OFFLINE${NC}"
}
echo -e "${BLUE}================================================================${NC}"
echo -e "   ARMBIAN PBX - ASTERISK 22 LTS + FREEPBX 17"
echo -e "   Web GUI: http://$IP_ADDR"
echo -e "${BLUE}================================================================${NC}"
EOF
chmod +x /etc/update-motd.d/99-pbx-status
rm -f /etc/motd

echo "========================================================"
echo "   FREEPBX INSTALLATION COMPLETE!"
echo "   Access: http://$(hostname -I | cut -d' ' -f1)/admin"
echo "========================================================"
