#!/system/bin/sh
# Post-install checks. Run as root on the phone:
#   adb shell su -c 'sh /data/local/tmp/verify.sh'
#
# Exercises the real path (Termux uid + app mount namespace), not a root shell.


fail=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; fail=1; }

# same trap as the launcher: Termux's coreutils chroot cannot exec in the rootfs
CHROOT=/system/bin/chroot
PATH=/system/bin:/system/xbin
export PATH

echo "rootfs"
[ -x /data/adb/opencode/alpine/usr/local/bin/opencode ] && ok "binary present" || bad "binary missing"

echo "boot service"
[ -x /data/adb/service.d/opencode.sh ] && ok "installed" || bad "missing"

echo "mounts"
grep -q " /data/adb/opencode/alpine/proc " /proc/self/mounts && ok "proc" || bad "proc not mounted"

echo "musl runtime"
chroot_ldd() { "$CHROOT" /data/adb/opencode/alpine /usr/bin/env PATH=/usr/bin:/bin:/sbin:/usr/sbin \
  /bin/sh -c 'ldd /usr/local/bin/opencode'; }
chroot_ldd >/dev/null 2>&1 \
  && ok "libstdc++ resolvable" || bad "libstdc++ missing - run install-device.sh"

echo "resolver"
grep -q '^nameserver' /data/adb/opencode/alpine/etc/resolv.conf && ok "resolv.conf present" || bad "no resolv.conf"

echo "launcher"
TU=$(cmd package list packages -U com.termux | sed 's/.*uid://')
[ -x /data/data/com.termux/files/usr/bin/opencode ] && ok "wrapper installed" || bad "wrapper missing"
if [ -x /data/adb/magisk/magisk ]; then
[ "$(/data/adb/magisk/magisk --sqlite "SELECT policy FROM policies WHERE uid=$TU;" | sed 's/.*=//')" = 2 ] \
  && ok "root policy allows uid $TU" || bad "no allow policy for uid $TU - re-run install-device.sh"
else
  echo "  skip  root policy check (Magisk not found)"
fi

echo "run"
P=$(pidof com.termux)
if [ -n "$P" ] && [ -n "$TU" ]; then
  /debug_ramdisk/su -t "$P" "$TU" /data/data/com.termux/files/usr/bin/opencode --version >/dev/null 2>&1 \
    && ok "opencode runs as the Termux app" || bad "launch failed as the app"
else
  bad "Termux not running - open it, then re-run"
fi

[ $fail = 0 ] && echo "all checks passed" || echo "some checks failed"
exit $fail
