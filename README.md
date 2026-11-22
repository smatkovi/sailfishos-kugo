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

The vendor overlay (Adreno GPU libraries and the patched gralloc), the fixup hook and the setup
script are in the image (droid-config-kugo). The Android images aren't shipped. One command,
as root, sets everything up:

```sh
devel-su kugo-waydroid-setup
```

It installs `waydroid`, `waydroid-runner` and `waydroid-settings` from sailfishos:chum. Then it
downloads LineageOS 17.1 VANILLA (system) and HALIUM_10 (vendor) from the Waydroid OTA index,
checks their SHA-256 and unpacks them to `/etc/waydroid-extra/images` (about 1.6 GB). Finally
it runs `waydroid init -f` and starts the container. Then start Android with the **Waydroid**
icon. The first boot takes several minutes, because the apps are compiled; later starts are
much quicker.

`kugo-waydroid-fixup` runs before every container start, so the following survive
`waydroid init -f` and package updates:

- `waydroid.cfg`: `vendor_type = HALIUM_10`, the custom images path, the `anbox-*` binder devices,
  and `aidl2` protocols.
- `config_nodes`: the `anbox-*` devices as source, not the host's binders. Otherwise
  servicemanager fails with "Device or resource busy".
- The overlay. 64-bit: the patched gralloc stack. 32-bit: the host's Adreno EGL and gralloc.
  Without them the 32-bit zygote aborts ("couldn't find an OpenGL ES implementation") and Android
  boots in a watchdog loop.
- `cgroups.json` without the memory controller and cgroup2. Kernel 4.4 has no cgroup namespaces,
  so the container's Android init otherwise locks the Sailfish session out of its cgroups:
  user services fail with `status=219/CGROUP`, and restarting the home screen leaves a blank
  screen.
- `dnsmasq.service` off. It comes in as a waydroid dependency and holds port 53, so every
  session ends at once ("Address already in use").
- The properties `ro.hardware.gralloc=kugo` and `persist.waydroid.no_background_subsurface=true`.
- `waydroid-runner` starts with `kugo-wlbuf.so` preloaded, which raises libwayland's 4 KiB client
  buffer limit to 1 MiB. Otherwise Android's composer falls behind while an app opens, is dropped
  ("error in client communication"), and the session ends.
- Only one launcher. The package's own runs `waydroid show-full-ui`, which on an uninitialised
  install would fetch the MAINLINE images that don't work here.

Crashes of Android processes in the container are not sent to the Sailfish crash reporter
(`kugo-core-filter`); Android keeps its own tombstones.

**Do not add any of the following to the overlay:** `hwcomposer.*.so`,
`android.hardware.graphics.composer@2.1-impl.so`, `android.hardware.graphics.mapper@2.0-impl.so`.
A vendor hwcomposer in the overlay makes SurfaceFlinger delegate composition to hardware that is
not reachable from the container (DEVICE instead of CLIENT composition), and the result is a
permanently black Waydroid window.

More background (in German):
[PORT-NOTES](https://github.com/smatkovi/droid-config-sony-loire/blob/kugo-sfos51/PORT-NOTES-kugo.md).

## Disclaimer

Flashing wipes your data and can brick your device. No warranty. Not affiliated
with Jolla or Sony.
Done (droid-config-kugo): the Waydroid helper (`kugo-waydroid-setup`); the EGL libraries, which
kugo-materialize-vendor-libs copies out of /mnt at every boot; the picture fix. The `kugo-jpeg-fix`
user service repairs saved photos (it inserts the missing JPEG DRI marker). The camera app's preview
of a new photo needs the same fix in gst-droid's droidcamsrc:
[ahjolinna/gst-droid](https://github.com/ahjolinna/gst-droid) (branches `kugo-dri-sfos51` and `kugo-dri-sfos52`).
