#!/bin/bash
# Script to generate the SSH login status banner (MOTD)
# Must be placed in /etc/update-motd.d/99-pbx-status and made executable (+x)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# System Info
UPTIME=$(uptime -p | cut -d " " -f 2-)
IP_ADDR=$(hostname -I | cut -d' ' -f1)
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')
RAM_USAGE=$(free -m | awk 'NR==2 {printf "%.1f%%", $3*100/$2 }')

# Service Status Helper
check_service() {
    systemctl is-active --quiet $1 && echo -e "${GREEN}ONLINE${NC}" || echo -e "${RED}OFFLINE${NC}"
}

ASTERISK_STATUS=$(check_service asterisk)
MARIADB_STATUS=$(check_service mariadb)
APACHE_STATUS=$(check_service apache2)

echo -e "${BLUE}"
echo "================================================================"
echo "   ARMBIAN PBX - ASTERISK 21 + FREEPBX 17 (ARM64)"
echo "================================================================"
echo -e "${NC}"
echo -e " System IP:    ${YELLOW}$IP_ADDR${NC}"
echo -e " Web GUI:      ${YELLOW}http://$IP_ADDR/admin${NC}"
echo -e " Uptime:       $UPTIME"
echo -e " Disk / RAM:   $DISK_USAGE / $RAM_USAGE"
echo -e ""
echo -e " Asterisk:     $ASTERISK_STATUS"
echo -e " MariaDB:      $MARIADB_STATUS"
echo -e " Apache Web:   $APACHE_STATUS"
echo -e "${BLUE}"
echo "================================================================"
echo -e "${NC}"