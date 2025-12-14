# Armbian Bookworm FreePBX 17 Installer (ARM64)

A vibe-coded, "one-click" installer for Asterisk 21 and FreePBX 17 on Debian 12 (ARM64).

**Disclaimer:** This is an amateur project created solely for my personal workflow to quickly deploy PBX systems on T95 Max+ TV boxes. I am hosting it here for my own convenience and storage. I do not expect anyone else to use this. It works for me, but it might not work for you. Use entirely at your own risk.

## Features
* **Fast Deployment:** Uses pre-compiled Asterisk 21 artifacts to skip long compilation times.
* **Modern Stack:** Debian 12 (Bookworm), FreePBX 17, PHP 8.2.
* **Optimized:** PHP memory limits tuned for low-RAM ARM devices.

## Installation
Requires a clean Armbian (Debian 12) installation and root access.

```bash
wget [https://raw.githubusercontent.com/slythel2/Armbian-FreePBX-17/main/install.sh](https://raw.githubusercontent.com/slythel2/Armbian-FreePBX-17/main/install.sh)
chmod +x install.sh
./install.sh
```
Access
Web Interface: http://<YOUR_IP>/admin

MariaDB Root Password: armbianpbx
