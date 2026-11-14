#!/system/bin/sh
# Magisk boot service script.
# Brings up the Alpine chroot that hosts opencode: pseudo-filesystems,
# external storage, and a working resolv.conf.
#
# Install to: /data/adb/service.d/opencode.sh (0755, root:root)


R=/data/adb/opencode/alpine
[ -f "$R/bin/busybox" ] || exit 0

mkdir -p "$R/dev/pts" "$R/proc" "$R/sys" "$R/etc" "$R/sdcard" "$R/root/projects"

mounted() { grep -q " $1 " /proc/self/mounts; }

mounted "$R/proc"    || mount -t proc proc "$R/proc"
mounted "$R/sys"     || mount -t sysfs sysfs "$R/sys"
mounted "$R/dev"     || mount -o bind /dev "$R/dev"
mounted "$R/dev/pts" || mount -o bind /dev/pts "$R/dev/pts"
mounted "$R/sdcard"  || mount -o bind /storage/emulated/0 "$R/sdcard"

# Android has no /etc/resolv.conf, and musl reads one. Wait for a default
# route, then write public resolvers plus the local gateway.
(
  i=0
  while [ $i -lt 120 ]; do
    gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
    [ -n "$gw" ] && break
    i=$((i+1)); sleep 1
  done
  printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n' > "$R/etc/resolv.conf"
  [ -n "$gw" ] && printf 'nameserver %s\n' "$gw" >> "$R/etc/resolv.conf"
) &
