#!/bin/bash

# ============================================================================
# AUTOMATED BUILD SCRIPT
# TARGET: Asterisk 22 LTS for Debian 12 (Bookworm)
# ============================================================================

# Stop execution on any error
set -e

# Function to display system status
sys_status() {
    echo "--- [DEBUG STATUS] ---"
    echo "Disk Space:"
    df -h / | tail -n 1
    echo "Memory Usage:"
    free -m
    echo "----------------------"
}

# Trap errors to provide logs
failure_handler() {
    echo ">>> [FATAL] Build failed at line $1"
    sys_status
    if [ -f "config.log" ]; then
        echo ">>> [DEBUG] Last 50 lines of Asterisk config.log:"
        tail -n 50 config.log
    fi
    if [ -f "third-party/pjproject/source/config.log" ]; then
        echo ">>> [DEBUG] Last 50 lines of PJProject config.log:"
        tail -n 50 third-party/pjproject/source/config.log
    fi
    exit 1
}

trap 'failure_handler $LINENO' ERR

ASTERISK_VER="$1"
[ -z "$ASTERISK_VER" ] && ASTERISK_VER="22-current"

BUILD_DIR="/usr/src/asterisk_build"
OUTPUT_DIR="/workspace"
DEBIAN_FRONTEND=noninteractive

echo ">>> [BUILDER] Starting build for version: $ASTERISK_VER"
sys_status

# 1. Install Build Dependencies
echo ">>> [BUILDER] Installing dependencies..."
apt-get update -qq

apt-get install -y -qq --no-install-recommends \
    build-essential libc6-dev linux-libc-dev gcc g++ \
    git curl wget subversion pkg-config \
    autoconf automake libtool binutils \
    libncurses5-dev libncursesw5-dev libxml2-dev libsqlite3-dev \
    libssl-dev uuid-dev libjansson-dev libedit-dev libxslt1-dev \
    libicu-dev libsrtp2-dev libopus-dev libvorbis-dev libspeex-dev \
    libspeexdsp-dev libgsm1-dev portaudio19-dev \
    unixodbc unixodbc-dev odbcinst libltdl-dev libsystemd-dev \
    python3 python3-dev

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
echo ">>> [BUILDER] Configuring Asterisk..."
# Check for problematic headers before configure
if grep -q "strtoq" /usr/include/stdlib.h; then
    echo ">>> [DEBUG] strtoq found in stdlib.h (Expected)"
fi
# Force detection of strtoq and set optimization to -O1 (back from -00 with fixed memory fault on Docker)
./configure --libdir=/usr/lib \
    --with-pjproject-bundled \
    --with-jansson \
    --without-x11 \
    --without-gtk2 \
    ac_cv_func_strtoq=yes \
    CFLAGS='-O1' \
    CXXFLAGS='-O1'

# 5. Clean potentially corrupted third-party builds
echo ">>> [BUILDER] Cleaning third-party artifacts..."
make -C third-party/pjproject clean || true
rm -rf third-party/jansson/dist || true

# 6. Module Selection
echo ">>> [BUILDER] Selecting modules..."
make menuselect.makeopts
menuselect/menuselect --enable format_mp3 menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-WAV menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-ULAW menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-ALAW menuselect.makeopts
menuselect/menuselect --enable CORE-SOUNDS-EN-GSM menuselect.makeopts
menuselect/menuselect --disable BUILD_NATIVE menuselect.makeopts

# 7. Compilation
echo ">>> [BUILDER] Compiling (Single core mode)..."
sys_status
# Using single core to prevent QEMU segmentation faults
make -j1

# 8. Install to Staging
echo ">>> [BUILDER] Creating installation structure..."
make install DESTDIR=$BUILD_DIR/staging
make samples DESTDIR=$BUILD_DIR/staging
make config DESTDIR=$BUILD_DIR/staging

# 9. Artifact Creation
echo ">>> [BUILDER] Final packaging..."
sys_status
cd $BUILD_DIR/staging
TAR_NAME="asterisk-${ASTERISK_VER}-arm64-debian12.tar.gz"

# Verify staging content size
du -sh .
tar -czvf "$OUTPUT_DIR/$TAR_NAME" .

echo ">>> [BUILDER] Success! Artifact created: $TAR_NAME"
