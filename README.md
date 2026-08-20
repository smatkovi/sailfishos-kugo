# Sailfish OS for Sony Xperia X Compact (kugo)

Community port of Sailfish OS 5.1.0.11 (Pispala) for the Sony Xperia X Compact
(F5321, msm8956), based on hybris-sony-aosp-8.1 with kernel 4.4.

**Working:** UI, telephony (calls/audio), mobile data, WLAN, Bluetooth, sensors,
fingerprint, camera (photo + video), Waydroid (Android apps) — out of the box.

Sources: [droid-config](https://github.com/smatkovi/droid-config-sony-loire/tree/kugo-sfos51) ·
[kernel](https://github.com/smatkovi/android_kernel_sony_msm/tree/kugo-sfos51)

## Prerequisites

- Xperia X Compact with **unlocked bootloader** (Sony official method;
  this permanently destroys the DRM keys)
- **Android 8.1 stock firmware** and the Sony AOSP **OEM binary v13
  (kernel 4.4, loire)** flashed at least once, **in this order** — the stock
  firmware includes `oem.sin` and overwrites the oem partition, so the OEM
  binary always goes last. The vendor blobs on /oem are required. Sony no longer lists
  these downloads prominently; working sources:
  - Stock firmware for F5321 (third-party XperiFirm archive, contains an
    `.ftf` bundle):
    <https://samsony.net/en/firmwares/sony/F5321/download/1660> —
    flash the `.ftf` with [Flashtool](https://github.com/Androxyde/Flashtool)
    (0.9.36.0, Linux tarball ships its own JRE; run `sudo ./FlashTool` and put
    the `.ftf` into `/root/.flashTool/firmwares/`, then lightning icon →
    Flashmode → tick all wipes → Flash). **Note:** `newflasher`/`xflasher` do
    NOT work — kugo (2016) speaks the old S1 flash protocol (USB id
    `0fce:adde`), newflasher only supports the 2017+ protocol (`0fce:b00b`).
    Flashmode = device off, hold **Volume-Down** + plug in USB (green LED);
    fastboot = hold **Volume-Up** + plug in USB (blue LED). The first Android
    boot after flashing may take 5–15 minutes and doesn't need to be completed
    — reaching the language screen is enough.
  - Sony OEM binary — MUST be the **kernel 4.4 v13** variant (SW_binaries_for_Xperia_Android_8.1.6.4_r1_v13_loire.zip); the kernel 4.9 binary does NOT work with this port:
    <https://opendevices.sony.net/file/download/software-binaries-for-aosp-oreo-android-8-1-kernel-4-4-loire-v13> —
    `fastboot flash oem SW_binaries_*loire*.img`
- PC with `adb`, `fastboot`, `lbzip2` (or `bzip2`)
- TWRP for kugo (twrp-3.7.0_9-0-kugo.img) from twrp.me. **Note:** the kugo
  bootloader does not support `fastboot boot`, so TWRP has to be flashed to
  the recovery partition (this overwrites any existing recovery).
- Files from the [latest release](../../releases): rootfs `*.tar.bz2` and
  `hybris-boot.img`

## Flashing

Put the release files and the TWRP image into one directory, then:

```sh
chmod +x flash-kugo.sh
./flash-kugo.sh <directory>
```

The script decompresses the rootfs locally (TWRP's busybox has no bunzip2),
flashes hybris-boot and TWRP via fastboot, then pauses: boot into TWRP by
holding **Power + Volume-Down** (the kugo bootloader cannot stream a
recovery via `fastboot boot`). After you confirm, it formats /data, pushes
the tar and extracts it to `/data/.stowaways/sailfishos` — the standard
hybris location where hybris-boot bind-mounts the rootfs from.

Manual steps, if you prefer doing it by hand:

```sh
lbzip2 -dk sfe-kugo-*.tar.bz2
fastboot flash boot hybris-boot.img
fastboot flash recovery twrp-3.7.0_9-0-kugo.img
# unplug USB, power off, hold Power + Volume-Down until TWRP appears
# (first TWRP start asks "Keep System Read Only?" - swipe to allow modifications)
# in TWRP: Wipe -> Format Data -> yes, then plug USB back in
adb push sfe-kugo-*.tar /data/rootfs.tar
adb shell 'mkdir -p /data/.stowaways/sailfishos && cd /data/.stowaways/sailfishos && tar --numeric-owner -xf /data/rootfs.tar && rm /data/rootfs.tar && sync'
adb reboot
```

## Waydroid setup

The required vendor overlay and libhybris build are already included in the
image. The Android system/vendor images are **not** shipped — download them
manually. Do not use plain `waydroid init`: it fetches MAINLINE images from
the OTA server, which do not work on this port.

- System: <https://sourceforge.net/projects/waydroid/files/images/system/lineage/waydroid_arm64/>
  (lineage-17.1 VANILLA arm64)
- Vendor: <https://sourceforge.net/projects/waydroid/files/images/vendor/waydroid_arm64/>
  (lineage-17.1 **HALIUM_10** arm64 — e.g.
  `lineage-17.1-20260402-HALIUM_10-waydroid_arm64-vendor.zip`)

Unzip both, put `system.img` and `vendor.img` into
`/etc/waydroid-extra/images/`, then as root:

```sh
waydroid init -f    # must report "found custom images"
```

After every `init -f` the following corrections are required
(`init -f` regenerates both files and reverts them each time). Verified
against a working device; run as root:

```sh
# (1)+(2) waydroid.cfg: HALIUM_10 vendor type, custom images path,
#         anbox-* binder devices, aidl2 protocols
CFG=/var/lib/waydroid/waydroid.cfg
sed -i \
  -e 's|^vendor_type *=.*|vendor_type = HALIUM_10|' \
  -e 's|^images_path *=.*|images_path = /etc/waydroid-extra/images|' \
  -e 's|^binder *=.*|binder = anbox-binder|' \
  -e 's|^vndbinder *=.*|vndbinder = anbox-vndbinder|' \
  -e 's|^hwbinder *=.*|hwbinder = anbox-hwbinder|' \
  $CFG
grep -q '^binder_protocol' $CFG || \
  sed -i '/^hwbinder/a binder_protocol = aidl2
service_manager_protocol = aidl2' $CFG
sed -i \
  -e 's|^binder_protocol *=.*|binder_protocol = aidl2|' \
  -e 's|^service_manager_protocol *=.*|service_manager_protocol = aidl2|' \
  $CFG

# (3) config_nodes: mount the anbox-* host devices, NOT the host binders
#     (source changes, the in-container target dev/... stays as is —
#      otherwise servicemanager fails with "Device or resource busy")
NODES=/var/lib/waydroid/lxc/waydroid/config_nodes
sed -i \
  -e 's|^lxc.mount.entry = /dev/binder dev/binder |lxc.mount.entry = /dev/anbox-binder dev/binder |' \
  -e 's|^lxc.mount.entry = /dev/vndbinder dev/vndbinder |lxc.mount.entry = /dev/anbox-vndbinder dev/vndbinder |' \
  -e 's|^lxc.mount.entry = /dev/hwbinder dev/hwbinder |lxc.mount.entry = /dev/anbox-hwbinder dev/hwbinder |' \
  $NODES

# dnsmasq blocks waydroid-net's listening socket on 192.168.240.1:
systemctl disable --now dnsmasq
```

Verify: `waydroid.cfg` must contain `vendor_type = HALIUM_10`, the three
`binder` entries pointing at `anbox-*`, both protocols `aidl2`; the three
binder lines in `config_nodes` must have `/dev/anbox-*` as source. More
background (in German): [PORT-NOTES](https://github.com/smatkovi/droid-config-sony-loire/blob/kugo-sfos51/PORT-NOTES-kugo.md).

**Do not add any of the following to /var/lib/waydroid/overlay:**
`hwcomposer.*.so`, `android.hardware.graphics.composer@2.1-impl.so`,
`android.hardware.graphics.mapper@2.0-impl.so`. A vendor hwcomposer in the
overlay makes SurfaceFlinger delegate composition to hardware that is not
reachable from the container (DEVICE instead of CLIENT composition) — the
result is a permanently black Waydroid window.

## Disclaimer

Flashing wipes your data and can brick your device. No warranty. Not affiliated
with Jolla or Sony.
