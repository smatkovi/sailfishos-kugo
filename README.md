# Sailfish OS for Sony Xperia X Compact (kugo)

Community port of Sailfish OS 5.1.0.11 (Pispala) for the Sony Xperia X Compact
(F5321, msm8956), based on hybris-sony-aosp-8.1 with kernel 4.4.

**Working:** UI, telephony (calls/audio), mobile data, WLAN, Bluetooth, sensors,
fingerprint, camera (photo + video), Waydroid (Android apps) — out of the box.

Sources: [droid-config](https://github.com/smatkovi/droid-config-sony-loire/tree/kugo-sfos51) ·
[kernel](https://github.com/smatkovi/android_kernel_sony_msm/tree/kugo-sfos51)

## Prerequisites

- Xperia X Compact with **unlocked bootloader** and Sony OEM/stock firmware
  flashed at least once (vendor blobs on /oem are required)
- PC with `adb`, `fastboot`, `lbzip2` (or `bzip2`)
- TWRP for kugo (twrp-3.7.0_9-0-kugo.img) — from twrp.me, used only via
  `fastboot boot`, your recovery partition is not touched
- Files from the [latest release](../../releases): rootfs `*.tar.bz2` and
  `hybris-boot.img`

## Flashing

Put the release files and the TWRP image into one directory, then:

```sh
chmod +x flash-kugo.sh
./flash-kugo.sh <directory>
```

The script decompresses the rootfs locally (TWRP's busybox has no bunzip2),
flashes hybris-boot via fastboot, boots TWRP once, formats /data after an
explicit confirmation, pushes the tar and extracts it directly to /data
(on kugo the /data partition root *is* the rootfs — no .stowaways subdir).

Manual steps, if you prefer doing it by hand:

```sh
lbzip2 -dk sfe-kugo-*.tar.bz2
fastboot flash boot hybris-boot.img
fastboot boot twrp-3.7.0_9-0-kugo.img
# in TWRP: Wipe -> Format Data -> yes
adb push sfe-kugo-*.tar /data/rootfs.tar
adb shell 'cd /data && tar --numeric-owner -xf rootfs.tar && rm rootfs.tar && sync'
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

After every `init -f`, apply the post-init corrections (init regenerates the
configs): in `/var/lib/waydroid/waydroid.cfg` set `vendor_type = HALIUM_10`,
switch binder/vndbinder/hwbinder to the `anbox-*` devices and set
`binder_protocol` / `service_manager_protocol` to `aidl2`; in
`/var/lib/waydroid/lxc/waydroid/config_nodes` point the binder mount entries
at the `anbox-*` device sources. Exact sed commands: see
[PORT-NOTES](https://github.com/smatkovi/droid-config-sony-loire/blob/kugo-sfos51/PORT-NOTES-kugo.md).

**Do not add any of the following to /var/lib/waydroid/overlay:**
`hwcomposer.*.so`, `android.hardware.graphics.composer@2.1-impl.so`,
`android.hardware.graphics.mapper@2.0-impl.so`. A vendor hwcomposer in the
overlay makes SurfaceFlinger delegate composition to hardware that is not
reachable from the container (DEVICE instead of CLIENT composition) — the
result is a permanently black Waydroid window.

## Disclaimer

Flashing wipes your data and can brick your device. No warranty. Not affiliated
with Jolla or Sony.
