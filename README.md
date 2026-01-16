# Armbian 12 Bookworm FreePBX 17 Installer (ARM64)

A vibe-coded, "one-click" installer for Asterisk 21 and FreePBX 17 on Debian 12 (ARM64).

**Disclaimer:** This is an amateur project created solely for my personal workflow to quickly deploy PBX systems on T95 Max+ TV boxes. I am hosting it here for my own convenience and storage. It works for me, **it should work on every ARM64 Debian 12 device** but it might not work for you. Use entirely at your own risk.

## **FreePBX 17 & Asterisk 21 Installer**
**Installation**
Requires a clean Armbian (Debian 12 Bookworm ARM64) installation and root access.

```bash
wget https://raw.githubusercontent.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/refs/heads/main/install.sh
chmod +x install.sh
./install.sh
```
Simply copy and paste.

## Features
* **One Click Install:** Every dependency Asterisk or FreePBX needs will be installed aswell.
* **Fast Deployment:** Uses pre-compiled Asterisk 21 artifacts to skip long compilation times.
* **Solid Stack:** Debian 12 (Bookworm), FreePBX 17, PHP 8.2.


Access
Web Interface: http://<YOUR_IP>/admin

MariaDB Root Password: armbianpbx


## (Extra Content) 
## Armbian 12 Image for T95 Max+ Android TV Box
<img src="https://github.com/user-attachments/assets/dd161989-dca9-49a2-a757-504306ed0648" width="30%">

You will also find a custom Armbian image in the **Releases** section of this repo.
* **Source:** Derived from ophub builds.
* **Target:** T95 Max+ (Amlogic S905X3 SoC).
* **Why:** I included a custom **auto-install script** that automatically corrects paths and selects the correct options and configurations specifically for this TV box.
* **Status:** Heavy WIP. Not polished, but functional for this project **IF YOU HAVE EXACTLY THE SAME TV BOX**
* **Features:** 2GB swap already configured.

# Instructions:
1. Burn it with Rufus or BalenaEtcher on a USB stick or SD Card
2. Remove the power cable, insert your USB stick/SD Card; there is a button at the bottom of the 3.5mm jack hole.
3. With a toothpick, apply pressure on the button until you hear a click, insert the power cable, keep the button pushed for 6-10 seconds.
4. It will automatically install and power off by itself.
5. Connect via ssh: root - 1234

# Important note for the boot sequence of the TVBOX after installation:
*Toothpick USB booting won't be usable anymore*

You can still force USB boot by nuking the eMMC:

```bash
dd if=/dev/zero of=/dev/mmcblk2 bs=1M count=1 && sync
```
and /reboot right after.

SD card boot, though, should always be the priority and boot from SD should work as far as I know.



**Credits**

slythel2,

ophub (for the base image),

FreePBX & Asterisk Open Source Projects.
