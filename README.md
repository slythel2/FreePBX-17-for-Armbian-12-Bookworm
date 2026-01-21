# Armbian 12 Bookworm FreePBX 17 Installer (ARM64)

One-click installer for Asterisk 22 LTS and FreePBX 17 on Debian 12 (ARM64).

A Github Workflow runs every 8 weeks, compiles the newest Asterisk 22 LTS release and uploads it on this repo, ensuring the installation comes with the latest official release.

## **FreePBX 17 & Asterisk 22 Installer**
**Installation**

Requires a clean Armbian (Debian 12 Bookworm ARM64) installation and root access.

```bash
wget https://raw.githubusercontent.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/refs/heads/main/install.sh
chmod +x install.sh
./install.sh
```
Simply copy and paste.

## Uninstall Script

```bash
wget https://raw.githubusercontent.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/refs/heads/main/uninstall.sh
chmod +x uninstall.sh
./uninstall.sh
```
This script completely removes the Asterisk, FreePBX, LAMP stack.

## Features
* **One Click Install:** Every dependency Asterisk or FreePBX needs will be installed aswell.
* **Fast Deployment:** Uses pre-compiled Asterisk 22 artifacts to skip long compilation times.
* **Solid Stack:** Debian 12 (Bookworm), FreePBX 17, Asterisk 22 LTS, PHP 8.2.


**Access**
**Web Interface**: http://<YOUR_IP>/admin

**MariaDB Root Password:** armbianpbx

-------------------------------

**Disclaimer:** This is an amateur project created with AI assistance solely for my personal workflow. I am hosting it here for my own convenience and storage.
It works for me, **it should work on every ARM64 Debian 12 device** but it *might* not work for you.

This project is **NOT** 100% vibe-coded. I don't have enough bash experience to create/maintain this project all on my own, but **I really wanted to make this work**, so I used AI assistance, mostly for debugging.

-------------------------------

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
