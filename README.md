<h1 align="center">A Script to install opencode on Android</h1>

<p align="center">
  Run <a href="https://opencode.ai">opencode</a>, the AI coding agent, natively on a rooted phone.<br>
  Double-click once on your PC. Type <code>opencode</code> in Termux. That's it.
</p>

<p align="center">
  <img alt="Android arm64" src="https://img.shields.io/badge/Android-arm64-3DDC84?logo=android&logoColor=white">
  <img alt="Root: Magisk" src="https://img.shields.io/badge/root-Magisk-00AF9C">
  <img alt="Installer: Windows" src="https://img.shields.io/badge/installer-Windows%20%7C%20any%20OS%20via%20adb-0078D4">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
</p>

<!-- Add a screenshot or GIF of opencode running in Termux here:
<p align="center"><img src="docs/demo.gif" width="320"></p> -->

---

## Why

opencode normally needs a laptop or a cloud box. This script puts it on the phone in your pocket: no emulator, no remote server, full speed. It sets up a tiny Alpine Linux environment under Magisk root, drops opencode into it, and gives you a plain `opencode` command in Termux.

## What you need

| | |
|---|---|
| **Phone** | arm64 Android, rooted with [Magisk](https://github.com/topjohnwu/Magisk). About 300 MB free and Wi-Fi. Most phones since 2017 are arm64. |
| **Computer** | Windows 10/11 for the one-click installer. macOS and Linux: use the [manual install](#manual-install-any-os). |
| **Cable** | A USB cable that carries data, not charge-only. |
| **Internet** | On the PC and the phone. The installer downloads about 90 MB. |

> Tested on a Pixel 3a with Magisk 31.1, on LineageOS 23 and stock Android 12. KernelSU and APatch are untested: the launcher tries them as a fallback, but you have to grant Termux root yourself.

## Install

**1. Enable USB debugging** (one time). Settings > About phone > tap **Build number** 7 times, then Settings > System > Developer options > **USB debugging**.

**2. Plug in and unlock the phone.** If asked "Allow USB debugging?", tick *Always allow* and tap **Allow**.

**3. Download this repo** (**Code > Download ZIP**) and **Extract All**. Don't run anything from inside the zip.

**4. Double-click `install-opencode.cmd`.** It does the rest:

```
  opencode  for Android

  ✓  Phone     Pixel 3a  ·  arm64  ·  root
  ✓  Termux    ready
  ✓  Alpine    3.24.4  ·  checksum ok
  ✓  opencode  210 MB
  ✓  Copy      10 files to the phone
  ✓  Install   done

  Restart the phone now? Needed once. [Y/n]
```

**5. Tap Grant on the phone** when Magisk asks *"Allow Shell to have superuser rights?"*. Missed it? Run the installer again.

**6. Restart the phone** when asked, then open **Termux** and type:

```sh
opencode
```

Inside opencode, run `/connect` to pick a model and sign in.

A red `x` means a step failed, and the line beside it says how to fix it. Fix it and run the installer again; it is safe to repeat. The log of the last run is `install.log`.

### Using it

- Quit with `Ctrl+C` or `/exit`.
- Your phone storage is `/sdcard` inside opencode. `/root/projects` is the default folder.
- **Keyboard not showing?** Tap the **KEYBOARD** key in Termux's extra-keys row. opencode turns on mouse mode, which hides the soft keyboard.

### What the installer checks first

| Situation | What happens |
|---|---|
| No `adb` | Downloads Google's platform-tools |
| No phone, locked, or not authorised | Says which, and how to fix it |
| More than one phone | Asks which one |
| Not arm64 | Stops |
| No root | Asks you to tap Grant, with help if the popup never shows |
| Termux missing | Installs it and waits for its first start |
| Less than ~300 MB free | Stops before installing, with the amount free |
| Phone offline | Tells you to turn on Wi-Fi |
| Bad or interrupted download | Resumes, verifies the Alpine checksum, rejects a corrupt archive |

### Common problems

| You see | Do this |
|---|---|
| `no phone found` | Charge-only cable, USB debugging off, or phone locked. |
| `the phone has not allowed this computer yet` | Unlock the phone and tap **Allow**. |
| `no root for adb` | Tap **Grant**. No popup? Magisk > **Superuser** > **Shell** > Allow, and Magisk settings > *Superuser access* = **Apps and ADB**. |
| `Termux would not install` | Play Protect blocked it: `adb shell settings put global verifier_verify_adb_installs 0`, then retry. |
| Stops at Termux | Open Termux, wait for the `$` prompt, run the installer again. |
| Permission denied in Termux | Run `install-opencode.cmd` again; it re-grants Termux root. |
| `the phone has no internet` | Turn on Wi-Fi or mobile data, run again. |
| `not enough free space` | Free some storage on the phone, run again. |

More in [Troubleshooting](#troubleshooting). To remove everything, double-click **`uninstall-opencode.cmd`**.

## Manual install (any OS)

Needs `adb`, plus arm64 and Magisk on the phone.

```sh
# Alpine minirootfs, aarch64
curl -L -o alpine.tar.gz https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/alpine-minirootfs-<version>-aarch64.tar.gz

# opencode, MUSL build (the glibc one needs a loader Android doesn't have)
curl -LO https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-arm64-musl.tar.gz
tar -xzf opencode-linux-arm64-musl.tar.gz && mv opencode opencode-bin
```

With the contents of `files/` in the same folder:

```sh
adb push alpine.tar.gz opencode-bin oc opencode-termux.sh opencode.json magisk-service.sh \
         termux.properties install-device.sh verify.sh uninstall-device.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/install-device.sh'
adb reboot
adb shell su -c 'sh /data/local/tmp/verify.sh'     # every line should say "ok"
```

Open Termux once before installing so it can bootstrap.

## How it works

opencode ships a `linux-arm64-musl` build that needs `ld-musl` and `libstdc++`. Android uses bionic and has no `/etc/resolv.conf`, so the binary needs a small musl userland around it. A `chroot` under Magisk `su` provides that with no syscall translation, so the TUI runs at native speed.

```
/data/adb/opencode/alpine/       Alpine minirootfs
├── usr/local/bin/opencode       the binary
├── usr/local/bin/oc             in-chroot launcher (sets PATH, HOME, TERM)
├── root/.config/opencode/       config
├── root/projects/               default working directory
├── sdcard                       bind mount of /storage/emulated/0
├── dev, proc, sys               bind mounts
└── etc/resolv.conf              written at boot

/data/adb/service.d/opencode.sh  boot service: mounts + resolv.conf
$PREFIX/bin/opencode             Termux launcher: su -> chroot -> oc
```

The rootfs lives under `/data/adb`, not `/data/local/tmp`, because apps can't execute from `shell_data_file`, and `/data/adb` is root-only and safe from temp cleanups.

```
install-opencode.cmd         Windows double-click installer (runs files/install-opencode.ps1)
uninstall-opencode.cmd       Windows double-click uninstaller
files/install-opencode.ps1   PC side: downloads, pushes over adb, starts the installer
files/*.sh, oc, ...          phone side: pushed to /data/local/tmp and run there as root
```

<details>
<summary><b>Things that will trip you up</b></summary>

1. **Never call `chroot` by name from Termux.** Termux's is the coreutils build and fails inside the rootfs with `failed to run command '/bin/sh'`, which looks like a missing rootfs. The launcher uses `/system/bin/chroot` (toybox).
2. **An app can't stat `/data/adb`.** Path tests in Termux say the rootfs is missing even when it isn't, so the launcher probes from inside the root shell and only accepts a rootfs containing `/usr/local/bin/oc`.
3. **Magisk's `su` runs `sh <script>`**, so the launcher runs under mksh: no bashisms. Arguments are forwarded as positionals, with a dummy `oc` as `$0`.
4. **The namespace flag is `-t 0`** (Magisk global namespace). `-m` means preserve-environment.
5. **The launcher finds `su` itself.** It tries `/debug_ramdisk/su`, then `su` on `PATH`, `/system/bin`, `/system/xbin` and `/sbin`, and uses the first that works.

</details>

## Configuration

The config is `<rootfs>/root/.config/opencode/opencode.json`, a normal opencode config. The one shipped here contains only `$schema`, and the installer always resets to it, keeping the old file as `opencode.json.bak`. Add providers with `/connect`; opencode stores keys under `<rootfs>/root/.local/share/opencode`.

**Keyboard:** the installer adds a **KEYBOARD** key to Termux's extra-keys row. If you use your own `termux.properties`, keep `'KEYBOARD'` in the `extra-keys` row (see `files/termux.properties`).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `su: permission denied` in Termux, no prompt | No Magisk allow policy for Termux. Re-run the installer (it writes policy **2** = allow). |
| `su: inaccessible or not found` from adb | Magisk's `su` is at `/debug_ramdisk/su`, not on `$PATH`. |
| `chroot: failed to run command '/bin/sh'` | A `chroot` from Termux's `PATH`, or no rootfs. Run `files/verify.sh`. |
| `chroot: failed to run command '/usr/local/bin/oc'` | A rootfs without `oc`. Run the installer. |
| `ls /data/adb/...` says *Permission denied* | Not a bug: `/data/adb` is root-only. |
| Commands `not found` inside chroot | Empty `PATH` from `su`. Launch through `oc`, which sets it. |
| `apk: DNS: transient error` | No usable resolver. Keep the LAN gateway first in `<rootfs>/etc/resolv.conf`. |
| `cp: ... Text file busy` | opencode is running. Close it and re-run. |
| TUI dies instantly | Run `ldd /usr/local/bin/opencode` in the chroot. A missing `libstdc++` means `apk add` never ran; re-run with the phone online. |

## Security

- Everything in the chroot runs as **root**. opencode has full device access by design.
- Policy `2` means Magisk never prompts for Termux again.
- The config is `0600`, root-owned and outside `/sdcard`.

## Uninstall

Windows: double-click `uninstall-opencode.cmd`. Elsewhere:

```sh
adb push files/uninstall-device.sh /data/local/tmp/
adb shell su -t 0 -c 'sh /data/local/tmp/uninstall-device.sh'
```

A copy also sits at `/data/adb/opencode/uninstall.sh`. The uninstaller unmounts the rootfs, including the `/sdcard` bind mount, before deleting, and refuses if a mount remains. **Never `rm -rf` the rootfs by hand while mounted**: it would delete your real shared storage through the bind mount. Revoking Termux's root grant in Magisk is left to you.

## Notes

- arm64 only. The glibc asset (`opencode-linux-arm64.tar.gz`) will not run; use the `-musl` one.
- Alpine is about 17 MB installed, the opencode binary about 210 MB.
- The boot service writes public resolvers plus the current LAN gateway. Adjust it if you run local DNS.

## License

MIT, see [LICENSE](LICENSE). opencode is MIT; Alpine packages keep their own licenses.
