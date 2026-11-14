#!/system/bin/sh
# On-device installer. Must run as ROOT on the phone:
#
#   adb push alpine.tar.gz opencode-bin oc opencode-termux.sh opencode.json \
#            magisk-service.sh termux.properties install-device.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/install-device.sh'
#
# Idempotent: re-running upgrades in place and is the fix for most breakage.
# Nothing is written outside /data/adb, /data/adb/service.d and Termux's prefix.


set -e

T=/data/local/tmp
R=/data/adb/opencode/alpine
S=/data/adb/service.d/opencode.sh

say() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root: adb shell su -c 'sh $T/install-device.sh'"

# Termux's PATH puts coreutils first, and its chroot cannot exec inside the
# rootfs ("failed to run command '/bin/sh'"). Always use toybox by absolute path.
CHROOT=/system/bin/chroot
PATH=/system/bin:/system/xbin
export PATH
[ "$(getprop ro.product.cpu.abi)" = "arm64-v8a" ] || die "arm64 device required (got $(getprop ro.product.cpu.abi))"
command -v cmd >/dev/null || die "cmd is missing from PATH"

for f in alpine.tar.gz opencode-bin oc opencode-termux.sh opencode.json magisk-service.sh termux.properties uninstall-device.sh; do
  [ -f "$T/$f" ] || die "missing $T/$f - see the Prepare section of README.md"
done

# Free space: rootfs + apk packages + binary need roughly 300 MB. Only matters
# on a first install (a re-run reuses the rootfs). df -k, 4th column = available KB.
NEED_KB=307200
if [ ! -f "$R/bin/busybox" ]; then
  mkdir -p /data/adb
  AVAIL=$(df -k /data 2>/dev/null | awk 'NR>1{a=$4} END{print a}')
  case "$AVAIL" in ''|*[!0-9]*) say "could not read free space - continuing" ;;
    *) [ "$AVAIL" -ge "$NEED_KB" ] || die "not enough free space on /data: $((AVAIL/1024)) MB free, need about $((NEED_KB/1024)) MB. Free some space and re-run." ;;
  esac
fi

# 1. rootfs (only extracted once)
if [ ! -f "$R/bin/busybox" ]; then
  say "extracting rootfs to $R"
  mkdir -p "$R"
  tar -xzf "$T/alpine.tar.gz" -C "$R" || die "extraction failed (corrupt tarball?)"
else
  say "rootfs already present at $R - reusing"
fi

# 2. pseudo-filesystems (the boot service re-creates these on every boot)
mkdir -p "$R/dev/pts" "$R/proc" "$R/sys" "$R/etc" "$R/sdcard" "$R/root/projects"
mkdir -p "$R/usr/local/bin" "$R/root/.config/opencode"
mounted() { grep -q " $1 " /proc/self/mounts; }
mounted "$R/proc"    || mount -t proc proc "$R/proc"
mounted "$R/sys"     || mount -t sysfs sysfs "$R/sys"
mounted "$R/dev"     || mount -o bind /dev "$R/dev"
mounted "$R/dev/pts" || mount -o bind /dev/pts "$R/dev/pts"
mounted "$R/sdcard"  || mount -o bind /storage/emulated/0 "$R/sdcard"

# 3. DNS. musl reads /etc/resolv.conf; Android has none and keeps the default
#    route hidden from `ip route`, so derive the LAN gateway from the address.
gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
if [ -z "$gw" ]; then
  gw=$(ip -4 addr show 2>/dev/null | awk '/inet 192\.168\./{split($2,a,"."); print a[1]"."a[2]"."a[3]".1"; exit}')
fi
{
  [ -n "$gw" ] && echo "nameserver $gw"
  echo "nameserver 1.1.1.1"
  echo "nameserver 8.8.8.8"
} > "$R/etc/resolv.conf"

# 4. musl runtime the opencode build links against
# Fail early with a plain message if the phone is offline (apk needs the network).
if ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1 && ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
  die "the phone has no internet. Turn on Wi-Fi or mobile data, then re-run (it is safe to repeat)."
fi
say "installing musl runtime (needs working DNS)"
"$CHROOT" "$R" /bin/sh -c '
  export PATH=/usr/sbin:/usr/bin:/sbin:/bin
  apk update && apk add --no-cache libstdc++ ca-certificates
' || die "apk add failed - check connectivity, then re-run this script"

# 5. binaries and config (rename, so a running opencode does not hold the inode:
#    plain cp onto a busy executable fails with "Text file busy")
cp "$T/opencode-bin" "$R/usr/local/bin/opencode.new" || die "copy failed"
mv -f "$R/usr/local/bin/opencode.new" "$R/usr/local/bin/opencode" || die "install failed"
cp "$T/oc"           "$R/usr/local/bin/oc.new" || die "copy failed"
mv -f "$R/usr/local/bin/oc.new" "$R/usr/local/bin/oc" || die "install failed"
chmod 755 "$R/usr/local/bin/opencode" "$R/usr/local/bin/oc"

# vanilla config: this build always takes the config from this folder, so a
# re-push can never resurrect previously saved providers or models. The old one
# is kept beside it as .bak.
CONF=$R/root/.config/opencode/opencode.json
[ -f "$CONF" ] && cp "$CONF" "$CONF.bak"
cp "$T/opencode.json" "$CONF"
chmod 600 "$CONF"

# 6. boot service, plus the uninstaller next to the rootfs (survives /data/local/tmp cleanups)
cp "$T/magisk-service.sh" "$S"
chmod 755 "$S"
cp "$T/uninstall-device.sh" /data/adb/opencode/uninstall.sh
chmod 755 /data/adb/opencode/uninstall.sh

# 7. Termux side: wrapper, extra-keys (the ⌨ toggle), and the root grant
TU=$(cmd package list packages -U com.termux 2>/dev/null | sed 's/.*uid://')
if [ -z "$TU" ]; then
  say "Termux not installed - launch it once, then re-run this script"
else
  P=/data/data/com.termux/files
  if [ ! -d "$P/usr/bin" ]; then
    say "Termux is not bootstrapped - open the app once, then re-run this script"
  else
    say "installing Termux wrapper and root grant for uid $TU"
    cp "$T/opencode-termux.sh" "$P/usr/bin/opencode"
    chmod 755 "$P/usr/bin/opencode"
    chown "$TU:$TU" "$P/usr/bin/opencode"

    mkdir -p "$P/home/.termux"
    cp "$T/termux.properties" "$P/home/.termux/termux.properties"
    chmod 600 "$P/home/.termux/termux.properties"
    chown -R "$TU:$TU" "$P/home/.termux"

    # policy 2 = allow (Magisk 27+ bitmask); 3 = apps+adb root access.
    # Magisk only. On KernelSU/APatch grant Termux root in their app instead.
    if [ -x /data/adb/magisk/magisk ]; then
      /data/adb/magisk/magisk --sqlite "INSERT OR REPLACE INTO settings (key,value) VALUES('root_access',3)"
      /data/adb/magisk/magisk --sqlite "INSERT OR REPLACE INTO policies (uid,policy,until,logging,notification) VALUES($TU,2,0,1,1)"
    else
      say "Magisk not found - open your root manager and allow superuser for Termux yourself"
    fi
  fi
fi

# 8. smoke test
say "smoke test"
"$CHROOT" "$R" /bin/sh -c 'export PATH=/usr/local/bin:/usr/bin:/bin HOME=/root; opencode --version' \
  || die "opencode did not run - see Troubleshooting in README.md"

say "done. reboot, then run 'opencode' in Termux."
