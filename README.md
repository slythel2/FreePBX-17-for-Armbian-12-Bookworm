# Armbian 12 Bookworm FreePBX 17 Installer (ARM64)

A vibe-coded, "one-click" installer for Asterisk 21 and FreePBX 17 on Debian 12 (ARM64).

**Disclaimer:** This is an amateur project created solely for my personal workflow to quickly deploy PBX systems on T95 Max+ TV boxes. I am hosting it here for my own convenience and storage. I do not expect anyone else to use this. It works for me, but it might not work for you. Use entirely at your own risk.

## The Armbian Image
You will also find a custom Armbian image in the **Releases** section of this repo.
* **Source:** Derived from ophub builds.
* **Target:** T95 Max+ (Amlogic S905X3 SoC).
* **Why:** I included a custom **auto-install script** that automatically corrects paths and selects the correct options and configurations specifically for this TV box.
* **Status:** Heavy WIP. Not polished, but functional for this project.

## Features
* **Fast Deployment:** Uses pre-compiled Asterisk 21 artifacts to skip long compilation times.
* **Modern Stack:** Debian 12 (Bookworm), FreePBX 17, PHP 8.2.
* **Optimized:** PHP memory limits tuned for low-RAM ARM devices.

## Installation
Requires a clean Armbian (Debian 12) installation and root access.

```bash
wget https://raw.githubusercontent.com/slythel2/FreePBX-17-for-Armbian-12-Bookworm/refs/heads/main/install.sh
chmod +x install.sh
./install.sh
```

Access
Web Interface: http://<YOUR_IP>/admin

MariaDB Root Password: armbianpbx

Note for T95 Max+
SD card boot should always be the priority as far as I know.
Since this is based on Amlogic build, after the installation the toothpick method to boot up via USB won't be usable anymore.
You can still force USB boot by nuking the eMMC:

```bash
echo 0 > /sys/block/mmcblk2boot0/force_ro
dd if=/dev/zero of=/dev/mmcblk2boot0 bs=1M count=1
dd if=/dev/zero of=/dev/mmcblk2 bs=1M count=1
sync
```


Credits

slythel2,

ophub (for the base image),

FreePBX & Asterisk Open Source Projects.
