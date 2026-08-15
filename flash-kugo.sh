#!/bin/bash
# flash-kugo.sh — SFOS-Image auf Xperia X Compact (kugo) flashen
# Workflow: etabliert beim v16clean-Flash (Aug 2026)
#   - Rootfs-bz2 wird LOKAL dekomprimiert (TWRPs busybox kann kein bunzip2!)
#   - hybris-boot via fastboot, TWRP nur per "fastboot boot" (recovery bleibt unberührt)
#   - kugo-Layout: mmcblk0p51-Wurzel IST das Rootfs -> tar direkt nach /data
#
# Aufruf:  ./flash-kugo.sh <image-verzeichnis>
# Beispiel: ./flash-kugo.sh ~/Downloads/kugo-flash/sfe-kugo-waydroidfix-20260815
#
# Voraussetzungen: adb, fastboot, lbzip2 (oder bzip2), TWRP-Image daneben oder in CWD

set -euo pipefail

IMGDIR="${1:?Aufruf: $0 <verzeichnis mit tar.bz2 + hybris-boot.img>}"
TWRP="${TWRP:-twrp-3.7.0_9-0-kugo.img}"

# --- Dateien finden -------------------------------------------------------
TARBZ2=$(ls "$IMGDIR"/*.tar.bz2 2>/dev/null | head -1) || true
BOOTIMG=$(ls "$IMGDIR"/hybris-boot.img 2>/dev/null | head -1) || true
[ -n "$TARBZ2" ]  || { echo "FEHLER: kein *.tar.bz2 in $IMGDIR"; exit 1; }
[ -n "$BOOTIMG" ] || { echo "FEHLER: kein hybris-boot.img in $IMGDIR"; exit 1; }
[ -f "$TWRP" ] || TWRP="$IMGDIR/$TWRP"
[ -f "$TWRP" ] || { echo "FEHLER: TWRP-Image nicht gefunden (TWRP=$TWRP setzen)"; exit 1; }

TAR="${TARBZ2%.bz2}"

echo "== Rootfs:  $TARBZ2"
echo "== Boot:    $BOOTIMG"
echo "== TWRP:    $TWRP"
echo

# --- 1. Dekomprimieren (TWRP kann kein bunzip2) ---------------------------
if [ ! -f "$TAR" ]; then
    echo "== Dekomprimiere (kann 1-2 Min dauern)..."
    if command -v lbzip2 >/dev/null; then lbzip2 -dk "$TARBZ2"
    else bzip2 -dk "$TARBZ2"; fi
fi
echo "== Entpackt: $(du -h "$TAR" | cut -f1)"

# --- 2. In den Bootloader -------------------------------------------------
echo
echo "== Geraet in den Fastboot-Modus bringen:"
echo "   - laeuft SFOS/Android mit adb: wird automatisch versucht"
echo "   - sonst: ausschalten, Vol-Up halten + USB anstecken (blaue LED)"
adb reboot bootloader 2>/dev/null || true
echo "== Warte auf fastboot..."
fastboot devices | grep -q . || { while ! fastboot devices | grep -q .; do sleep 2; done; }
fastboot devices

# --- 3. Boot flashen, TWRP einmalig booten --------------------------------
echo
echo "== Flashe hybris-boot..."
fastboot flash boot "$BOOTIMG"
echo "== Boote TWRP (einmalig, recovery-Partition bleibt unberuehrt)..."
fastboot boot "$TWRP"

echo
echo "== Warte auf TWRP/adb..."
adb wait-for-device
sleep 3

# --- 4. Data formatieren ---------------------------------------------------
echo
read -rp ">> ACHTUNG: /data wird GELOESCHT (Format Data). Fortfahren? [yes/NO] " ANS
[ "$ANS" = "yes" ] || { echo "Abgebrochen."; exit 1; }
# Format Data via twrp-Kommando (zuverlaessiger als wipe bei f2fs/ext4-Wechseln)
adb shell twrp format data || { echo "twrp format data fehlgeschlagen - in TWRP manuell: Wipe -> Format Data -> yes; dann Enter"; read -r; }
sleep 2
adb shell mount /data 2>/dev/null || true

# --- 5. Rootfs pushen & entpacken ------------------------------------------
echo
echo "== Push Rootfs-Tar ($(du -h "$TAR" | cut -f1)) - dauert ein paar Minuten..."
adb push "$TAR" /data/rootfs.tar
echo "== Entpacke auf dem Geraet..."
adb shell 'cd /data && tar --numeric-owner -xf rootfs.tar && rm rootfs.tar && sync'

# --- 6. Reboot --------------------------------------------------------------
echo
echo "== Fertig - Reboot ins frische SFOS..."
adb reboot

echo
echo "=============================================================="
echo "Nach dem ersten Boot (Ersteinrichtung abwarten):"
echo "  zypper se -i waydroid"
echo "  ls /var/lib/waydroid/overlay/vendor/lib64/    # 15 Dateien?"
echo "  rpm -qa | grep libhybris                      # 2b39e63?"
echo "Dann waydroid init gemaess PORT-NOTES (HALIUM_10)."
echo "=============================================================="
