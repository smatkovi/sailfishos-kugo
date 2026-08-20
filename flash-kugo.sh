#!/bin/bash
# flash-kugo.sh — flash a SailfishOS image to the Sony Xperia X Compact (kugo)
# v2: the kugo bootloader does NOT support 'fastboot boot'
#     (thanks ahjolinna) -> TWRP is flashed to the recovery
#     partition and booted via key combination.
#
# Workflow:
#   - the rootfs .bz2 is decompressed LOCALLY (TWRP's busybox has no bunzip2!)
#   - hybris-boot + TWRP are flashed via fastboot
#   - standard hybris layout: hybris-boot bind-mounts
#     /data/.stowaways/sailfishos as the rootfs -> tar extracts there
#
# Usage:   ./flash-kugo.sh <image-directory>
# Example: ./flash-kugo.sh ~/Downloads/kugo-flash/sfe-kugo-waydroidfix-20260815
#
# Requirements: adb, fastboot, lbzip2 (or bzip2), TWRP image next to the
# script or in the image directory. Stock firmware + Sony OEM binary v13
# must have been flashed once (see README).

set -euo pipefail

IMGDIR="${1:?Usage: $0 <directory with tar.bz2 + hybris-boot.img>}"
TWRP="${TWRP:-twrp-3.7.0_9-0-kugo.img}"

# --- locate files ----------------------------------------------------------
TARBZ2=$(ls "$IMGDIR"/*.tar.bz2 2>/dev/null | head -1) || true
BOOTIMG=$(ls "$IMGDIR"/hybris-boot.img 2>/dev/null | head -1) || true
[ -n "$TARBZ2" ]  || { echo "ERROR: no *.tar.bz2 in $IMGDIR"; exit 1; }
[ -n "$BOOTIMG" ] || { echo "ERROR: no hybris-boot.img in $IMGDIR"; exit 1; }
[ -f "$TWRP" ] || TWRP="$IMGDIR/$TWRP"
[ -f "$TWRP" ] || { echo "ERROR: TWRP image not found (set TWRP=/path/to/twrp.img)"; exit 1; }

TAR="${TARBZ2%.bz2}"

echo "== Rootfs:  $TARBZ2"
echo "== Boot:    $BOOTIMG"
echo "== TWRP:    $TWRP"
echo
echo "!! NOTE: TWRP will be FLASHED to the recovery partition"
echo "!! (the kugo bootloader does not support 'fastboot boot')."
echo "!! Any existing recovery will be overwritten."
echo

# --- 1. decompress (TWRP has no bunzip2) -----------------------------------
if [ ! -f "$TAR" ]; then
    echo "== Decompressing (may take 1-2 minutes)..."
    if command -v lbzip2 >/dev/null; then lbzip2 -dk "$TARBZ2"
    else bzip2 -dk "$TARBZ2"; fi
fi
echo "== Decompressed: $(du -h "$TAR" | cut -f1)"

# --- 2. enter the bootloader -------------------------------------------------
echo
echo "== Put the device into fastboot mode:"
echo "   - if SFOS/Android with adb is running: attempted automatically"
echo "   - otherwise: power off, hold Vol-UP + plug in USB (blue LED)"
adb reboot bootloader 2>/dev/null || true
echo "== Waiting for fastboot..."
fastboot devices | grep -q . || echo "   (nothing happening? check permissions: on Arch install 'android-udev', or run with sudo)"
fastboot devices | grep -q . || { while ! fastboot devices | grep -q .; do sleep 2; done; }
fastboot devices

# --- 3. flash boot + TWRP -----------------------------------------------------
echo
echo "== Flashing hybris-boot..."
fastboot flash boot "$BOOTIMG"
echo "== Flashing TWRP to recovery..."
fastboot flash recovery "$TWRP"

echo
echo "=============================================================="
echo ">> NOW BOOT INTO TWRP MANUALLY:"
echo "   1. unplug the USB cable"
echo "   2. power the device off (hold Power if needed)"
echo "   3. hold Power + Volume-DOWN until TWRP appears"
echo "   4. plug the USB cable back in"
echo "=============================================================="
read -rp ">> Press Enter once TWRP is running and USB is connected... " _

echo "== Waiting for TWRP/adb..."
adb wait-for-device
sleep 3

# --- 4. format data ------------------------------------------------------------
echo
read -rp ">> WARNING: /data will be ERASED (Format Data). Continue? [yes/NO] " ANS
[ "$ANS" = "yes" ] || { echo "Aborted."; exit 1; }
adb shell twrp format data || { echo "twrp format data failed - in TWRP do: Wipe -> Format Data -> yes; then press Enter"; read -r; }
sleep 2
adb shell mount /data 2>/dev/null || true

# --- 5. push & extract rootfs ---------------------------------------------------
echo
echo "== Pushing rootfs tar ($(du -h "$TAR" | cut -f1)) - takes a few minutes..."
adb push "$TAR" /data/rootfs.tar
echo "== Extracting to /data/.stowaways/sailfishos (hybris-boot expects the rootfs there)..."
adb shell 'mkdir -p /data/.stowaways/sailfishos && cd /data/.stowaways/sailfishos && tar --numeric-owner -xf /data/rootfs.tar && rm /data/rootfs.tar && sync'
echo "== Verifying rootfs..."
adb shell 'test -f /data/.stowaways/sailfishos/etc/sailfish-release && echo ROOTFS_OK' | grep -q ROOTFS_OK \
    || { echo "ERROR: etc/sailfish-release not found under /data/.stowaways/sailfishos - extraction failed, NOT rebooting."; exit 1; }

# --- 6. reboot -------------------------------------------------------------------
echo
echo "== Done - rebooting into fresh SFOS..."
adb reboot

echo
echo "=============================================================="
echo "After first boot (let the setup wizard finish):"
echo "  zypper se -i waydroid"
echo "  ls /var/lib/waydroid/overlay/vendor/lib64/    # 15 files?"
echo "  rpm -qa | grep libhybris                      # 2b39e63?"
echo "Then set up Waydroid as described in the README (init -f + sed fixes)."
echo "=============================================================="
