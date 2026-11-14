#!/system/bin/sh
# Remove everything this project installs: boot service, Termux launcher, rootfs.
#
# The installer leaves a copy at /data/adb/opencode/uninstall.sh, so run:
#   adb shell su -t 0 -c 'sh /data/adb/opencode/uninstall.sh'
#
# `su -t 0` matters: the mounts were made in the magisk global namespace, and a
# plain `su -c` runs in the app's namespace where they are invisible - the mount
# check would then pass on a still-mounted rootfs and rm -rf would walk into the
# /sdcard bind mount, i.e. into your real photos.
#
# From a fresh checkout the script may not be on the phone yet; push and use the
# temp path in that case:
#   adb push files/uninstall-device.sh /data/local/tmp/
#   adb shell su -t 0 -c 'sh /data/local/tmp/uninstall-device.sh'


# Ask before deleting anything. Skipped when the caller already confirmed
# (the .cmd asks, then passes ASSUME_YES=1) and when there is no terminal to
# ask on at all (adb without a pty, the boot service, a pipe) - an automated
# run has nobody to answer, and the .cmd is the flow that does the asking.
confirm() {
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  if [ -t 0 ]; then
    _in=/dev/stdin
  elif ( : < /dev/tty ) 2>/dev/null; then
    _in=/dev/tty
  else
    return 0
  fi
  printf 'Delete opencode from this device? [y/N] '
  _ans=
  if ! read -r _ans < "$_in" 2>/dev/null; then
    # nothing could be read (a pty nobody types into, EOF): this is an
    # automated run, not a person answering, so do not block or fake a "no"
    echo
    echo "(no input available - automated run, continuing)"
    return 0
  fi
  echo
  case "$_ans" in
    [yY]|[yY][eE][sS]) return 0 ;;
  esac
  echo "cancelled: nothing was deleted."
  exit 0
}

# This file is the phone-side script. Started on a computer (Git Bash, WSL,
# macOS) it can only fail confusingly - /system/bin and /data/adb are Android's.
if [ ! -d /system/bin ] || [ ! -d /data ]; then
  echo "ERROR: this is the ON-DEVICE uninstaller, and this is not the phone." >&2
  echo "       kernel: $(uname -s 2>/dev/null)  cwd: $(pwd)" >&2
  echo "       On Windows, close this and double-click uninstall-opencode.cmd" >&2
  echo "       (the .cmd in the folder above files\\ - it drives adb for you)." >&2
  exit 1
fi
R=/data/adb/opencode/alpine
BASE=/data/adb/opencode

# Get root here, whatever way this was started: a double-click, `sh
# /data/adb/opencode/uninstall.sh` in Termux, or a plain adb shell that forgot
# `su`. `exec` hands the process over, so the root copy is the only one that
# runs (no double output). It must be su -t 0: the bind mounts live in the
# magisk global namespace.
#
# If no su binary runs at all, say so and stop - better than half-uninstalling.
if [ "$(id -u)" != 0 ]; then
  # guards against a su that runs the command without changing uid, which
  # would otherwise re-exec itself forever
  if [ "${OPENCODE_SU_RETRY:-0}" = 1 ]; then
    echo "ERROR: su did not give root (still uid $(id -u))." >&2
    exit 1
  fi
  SELF=$0
  case "$SELF" in
    /*) ;;
    *) SELF="$(pwd)/$SELF" ;;
  esac
  # probe before exec: a failed `exec` in mksh kills the script, so the loop
  # below would never reach the second candidate or the error message
  su_bin=
  for s in /debug_ramdisk/su /system/bin/su /sbin/su /system/xbin/su; do
    if [ -x "$s" ]; then
      su_bin=$s
      break
    fi
  done
  if [ -z "$su_bin" ]; then
    s=$(command -v su 2>/dev/null)
    [ -n "$s" ] && su_bin=$s
  fi
  if [ -z "$su_bin" ]; then
    echo "ERROR: cannot get root from here - no su binary is reachable." >&2
    echo "  uid       : $(id -u)" >&2
    echo "  kernel    : $(uname -s 2>/dev/null)" >&2
    echo "  directory : $(pwd)" >&2
    if [ -f /etc/alpine-release ]; then
      echo "  this is the OPENCODE ENVIRONMENT, not Android. Nothing outside the" >&2
      echo "  chroot (/data/adb, /debug_ramdisk, your Termux bin) exists in here," >&2
      echo "  so it cannot uninstall itself. Type 'exit' to leave opencode, then" >&2
      echo "  run it from Termux ('su -c ...') or double-click the .cmd on Windows." >&2
    else
      if [ ! -d /system/bin ] || [ ! -d /data ]; then
        echo "  this is NOT the phone: $0 is the on-device script and it only" >&2
        echo "  works on Android (it needs /system/bin and /data/adb)." >&2
        echo "  On this computer, double-click uninstall-opencode.cmd instead -" >&2
        echo "  that is the one that talks to the phone over adb." >&2
      else
        echo "  looked for: /debug_ramdisk/su /system/bin/su /sbin/su /system/xbin/su," >&2
        echo "              then 'su' on PATH (found: ${PATH:-<empty>})" >&2
        echo "  Magisk puts su at /debug_ramdisk/su. If that is missing, reinstall" >&2
        echo "  Magisk; meanwhile the double-click uninstaller on Windows works" >&2
        echo "  over adb and does not need su from this shell." >&2
      fi
    fi
    exit 1
  fi
  exec "$su_bin" -t 0 -c "OPENCODE_SU_RETRY=1 ASSUME_YES=${ASSUME_YES:-0} sh $SELF"
fi

# nothing has been touched up to here - this is the last gate before deleting
confirm

# remember what was actually there, so a second run can report "nothing to do"
found=0
[ -d "$R" ] && found=1
[ -f /data/adb/service.d/opencode.sh ] && found=1
[ -f /data/data/com.termux/files/usr/bin/opencode ] && found=1

rm -f /data/adb/service.d/opencode.sh
rm -f /data/data/com.termux/files/usr/bin/opencode

# The rootfs has /sdcard (your real shared storage), /dev, /proc and /sys
# bind-mounted into it. `rm -rf` on a live rootfs walks through those and
# deletes your photos and files. Unmount everything first, deepest first,
# and refuse to delete if anything is still mounted.
if [ -d "$R" ]; then
  for i in 1 2 3; do
    grep " $R/" /proc/self/mounts | awk '{print $2}' | sort -r | while read -r m; do
      umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null
    done
    sleep 1
  done
  if grep -q " $R" /proc/self/mounts; then
    echo "ERROR: still mounted under $R - reboot, then run this script again (nothing deleted)" >&2
    grep " $R" /proc/self/mounts >&2
    exit 1
  fi
  rm -rf "$R" || exit 1
fi

# drop this script and the now-empty base dir last; the running copy stays
# readable because sh holds the file descriptor open
rm -f "$BASE/uninstall.sh"
rmdir "$BASE" 2>/dev/null

if [ "$found" = 0 ]; then
  echo "nothing to remove: opencode was not installed on this device."
  exit 0
fi
echo "removed: boot service, Termux launcher, rootfs and its config (API key included)."
echo "left to you: revoke Termux's root grant in Magisk and drop the extra-keys line."
