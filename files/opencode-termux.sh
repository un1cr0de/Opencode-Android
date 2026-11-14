#!/data/data/com.termux/files/usr/bin/bash
# Termux-side launcher for opencode on Android.
#
# Why it looks odd:
#  - an app cannot stat /data/adb (0700 root) or execute /data/local/tmp
#    (shell_data_file), so ANY path test here lies. The rootfs is therefore
#    probed inside the root shell, where both are readable.
#  - chroot is called as /system/bin/chroot, never by name. Termux's PATH
#    resolves `chroot` to the coreutils build, which in the app's mount
#    namespace fails inside the rootfs with "failed to run command
#    '/bin/sh': No such file or directory" - which looks exactly like a
#    missing rootfs. Toybox (Android's) has no such problem.
#  - PATH is forced to the Android default for the same reason.
#  - a rootfs only counts if it really contains /usr/local/bin/oc, and oc is
#    started as `/bin/sh /usr/local/bin/oc` (shebang never resolved, exec bit
#    not required). If none qualifies it lists what it saw.
#  - magisk su runs `sh <script>`, so this shebang is NOT honoured and the
#    launcher actually runs under mksh: no bashisms. mksh's printf has no %q,
#    so arguments are forwarded as positionals (su keeps them intact) with a
#    dummy "oc" swallowed as $0.
#  - -t 0 = magisk global mount namespace. `-m` is preserve-environment and
#    `-mm` is not a namespace flag.

# Find a working su. Magisk's lives at /debug_ramdisk/su (not on PATH); other
# root managers (KernelSU, APatch) put theirs on PATH or in /system/bin.
# Only Magisk's takes -t 0; the others get no namespace flag. Untested on
# KernelSU/APatch - this is a best-effort fallback.
SU=""; TFLAG=""
for c in /debug_ramdisk/su su /system/bin/su /system/xbin/su /sbin/su; do
  if "$c" -c true >/dev/null 2>&1; then SU=$c; break; fi
done
if [ -z "$SU" ]; then
  echo "opencode: no working su found (tried /debug_ramdisk/su, PATH, /system/bin, /system/xbin, /sbin)." >&2
  echo "  Is the phone rooted, and did you grant Termux superuser rights? Open your root manager > Superuser > Termux > Allow." >&2
  exit 1
fi
[ "$SU" = /debug_ramdisk/su ] && TFLAG="-t 0"

exec "$SU" $TFLAG -c '
PATH=/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/system_ext/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin
export PATH
for R in /data/adb/opencode/alpine /data/local/tmp/alpine; do
  [ -d "$R" ] || continue
  [ -f "$R/usr/local/bin/oc" ] || continue
  chmod 755 "$R/usr/local/bin/oc" 2>/dev/null
  exec /system/bin/chroot "$R" /bin/sh /usr/local/bin/oc "$@"
done

echo "opencode: no usable rootfs (need one with /usr/local/bin/oc) - run files/install-device.sh" >&2
echo "--- what was found ---" >&2
for R in /data/adb/opencode/alpine /data/local/tmp/alpine; do
  printf "%s: " "$R" >&2
  ls -ld "$R" 2>&1 | sed "s|^| |" >&2
  for f in bin/sh usr/local/bin/oc etc/resolv.conf; do
    printf "  %-24s " "$f" >&2
    ls -l "$R/$f" 2>&1 | sed "s|^| |" >&2
  done
done
exit 1' oc "$@"
