#!/bin/bash

# ============================================================================
# AUTOMATED BUILD SCRIPT (Executed inside the ARM64 container)
# TARGET: Asterisk 22 LTS for Debian 12 (Bookworm)
# ============================================================================

# Stop execution on any error
set -e

ASTERISK_VER="$1"
[ -z "$ASTERISK_VER" ] && ASTERISK_VER="22-current"

BUILD_DIR="/usr/src/asterisk_build"
OUTPUT_DIR="/workspace"
DEBIAN_FRONTEND=noninteractive

echo ">>> [BUILDER] Starting build for version: $ASTERISK_VER"

# 1. Install Build Dependencies (inside the container)
echo ">>> [BUILDER] Installing dependencies..."
apt-get update -qq
apt-get install -y -qq \
    git curl wget build-essential subversion pkg-config \
    libncurses5-dev libncursesw5-dev libxml2-dev libsqlite3-dev \
    libssl-dev uuid-dev libjansson-dev libedit-dev libxslt1-dev \
    libicu-dev libsrtp2-dev libopus-dev libvorbis-dev libspeex-dev \
    libspeexdsp-dev libgsm1-dev portaudio19-dev \
    unixodbc unixodbc-dev odbcinst libltdl-dev

mkdir -p $BUILD_DIR
cd $BUILD_DIR

# 2. Download Sources
echo ">>> [BUILDER] Downloading Asterisk sources..."
wget -qO asterisk.tar.gz "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VER}.tar.gz"
tar -xzf asterisk.tar.gz --strip-components=1
rm asterisk.tar.gz

# 3. Download MP3 Sources
echo ">>> [BUILDER] Downloading MP3 resources..."
contrib/scripts/get_mp3_source.sh

# 4. Configuration
# --with-pjproject-bundled: CRITICAL. Uses the internal PJPROJECT version for VoIP stability.
echo ">>> [BUILDER] Configuring..."
./configure --libdir=/usr/lib --with-pjproject-bundled --with-jansson-bundled --without-x11 --without-gtk2

# 5. Module Selection (Headless)
echo ">>> [BUILDER] Selecting modules..."
make menuselect.makeopts
menuselect/menuselect --enable format_mp3 menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-WAV menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-ULAW menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-ALAW menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-GSM menuselect.makeopts
# Note: BUILD_NATIVE disabled to ensure generic ARM64 compatibility (S905X3)
menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts

# 6. Compilation
echo ">>> [BUILDER] Compiling on $(nproc) cores..."
make -j$(nproc)

# 7. Install to temporary directory (Staging)
echo ">>> [BUILDER] Creating installation structure..."
make install DESTDIR=$BUILD_DIR/staging
make samples DESTDIR=$BUILD_DIR/staging
make config DESTDIR=$BUILD_DIR/staging

# 8. Artifact Creation (.tar.gz)
echo ">>> [BUILDER] Final packaging..."
cd $BUILD_DIR/staging
# Standardized filename that your install.sh will look for
TAR_NAME="asterisk-${ASTERISK_VER}-arm64-debian12.tar.gz"
tar -czvf "$OUTPUT_DIR/$TAR_NAME" .

echo ">>> [BUILDER] Success! Artifact created: $TAR_NAME"
