#!/bin/bash
# Runs roles/swap against a real swap file: it creates, resizes and turns swap
# files on and off. Run it only on a throwaway machine (CI sets CI=true).
set -uo pipefail

if [ "${CI:-}" != true ]; then
  echo "run this only on a throwaway machine (it needs CI=true)" >&2
  exit 2
fi
cd "$(dirname "$0")/../.." || exit 2

F=/swaptest.img
MIB=$((1024 * 1024))
LOG=$(mktemp)
BIN=$(mktemp -d)
chmod 755 "$BIN"
failures=0

cleanup() {
  sudo swapoff "$F" 2>/dev/null
  sudo rm -f "$F" "$F.new" "$F.old"
  sudo rm -rf "$BIN"
  rm -f "$LOG"
}
trap cleanup EXIT

# Runs the role; its exit status is left in rc and its output in $LOG.
play() {
  uvx -q --from 'ansible-core>=2.22,<2.23' ansible-playbook tests/swap/swap.yml \
    -e swap_file="$F" "$@" >"$LOG" 2>&1
  rc=$?
}
changed() { grep -oE 'changed=[0-9]+' "$LOG" | tail -1 | cut -d= -f2; }
logged() { grep -qF "$1" "$LOG"; }
active() { awk -v f="$F" '$1 == f { found = 1 } END { exit !found }' /proc/swaps; }
size_mib() { echo $(($(stat -c %s "$F") / MIB)); }
# The file has this size, is active, and no .new or .old is left beside it.
state_is() { [ "$(size_mib)" = "$1" ] && active && [ ! -e "$F.new" ] && [ ! -e "$F.old" ]; }

check() { # description, then a command that must succeed
  local what=$1
  shift
  if "$@"; then
    echo "PASS $what"
  else
    echo "FAIL $what"
    sed 's/^/    /' "$LOG"
    failures=$((failures + 1))
  fi
}
ok() { [ "$rc" -eq 0 ]; }
failed_with() { [ "$rc" -ne 0 ] && logged "$1"; }
unchanged() { ok && [ "$(changed)" = 0 ]; }

sudo fallocate -l 256M "$F"
sudo chmod 600 "$F"
sudo mkswap "$F" >/dev/null
sudo swapon "$F"
echo "start: $F is 256 MiB and active"

play -e swap_size=512M --check
check "check mode reports the resize" bash -c "[ $rc -eq 0 ] && grep -qF 'Resizing $F' '$LOG'"
check "and leaves the file at 256 MiB" state_is 256

play -e swap_size=512M
check "grow to 512 MiB" ok
check "the file is 512 MiB, active, with nothing left over" state_is 512

play -e swap_size=512M
check "a rerun at the same size changes nothing" unchanged

play -e swap_size=384M
check "shrink to 384 MiB" ok
check "the file is 384 MiB, active, with nothing left over" state_is 384

play -e swap_size=512M -e swap_resize_ram_margin=1P
check "a resize that would not fit in memory fails" failed_with "emptying it needs"
check "and leaves the old swap active at 384 MiB" state_is 384

play -e swap_size=100T
check "a resize that would not fit on the disk fails" failed_with "the new file needs"
check "and leaves the old swap active at 384 MiB" state_is 384

# Failures after the old swap is off, from stand-ins first on PATH: the switch
# has to put the old file back and turn it on again.
printf '#!/bin/sh\necho "ln: injected failure" >&2\nexit 1\n' >"$BIN/ln"
chmod +x "$BIN/ln"
play -e swap_size=512M -e swap_test_bin="$BIN"
check "a hard link that fails after swapoff fails the run" failed_with "could not keep the old swap file"
check "and turns the old swap back on at 384 MiB" state_is 384
rm -f "$BIN/ln"

# Fails once (for the new file), then runs the real swapon (for the old one).
cat >"$BIN/swapon" <<EOF
#!/bin/sh
if [ ! -e "$BIN/swapon.failed" ]; then
  touch "$BIN/swapon.failed"
  echo "swapon: injected failure" >&2
  exit 1
fi
exec /usr/sbin/swapon "\$@"
EOF
chmod +x "$BIN/swapon"
play -e swap_size=512M -e swap_test_bin="$BIN"
check "a new swap file that fails to turn on fails the run" failed_with "could not turn on the new swap file"
check "and the old swap is back and active at 384 MiB" state_is 384
check "the stand-in failed exactly once" test -e "$BIN/swapon.failed"
rm -f "$BIN/swapon" "$BIN/swapon.failed"

sudo swapoff "$F"
play -e swap_size=512M
check "an inactive swap file is reported and left alone" bash -c "[ $rc -eq 0 ] && grep -qF 'is not active swap' '$LOG' && [ '$(changed)' = 0 ]"
check "and is still 384 MiB" bash -c "[ $(size_mib) = 384 ]"
sudo swapon "$F"

play -e swap_size=512M -e swap_file=/no-such-swap.img
check "a missing swap file is reported and not created" bash -c "[ $rc -eq 0 ] && grep -qF 'is missing' '$LOG' && [ ! -e /no-such-swap.img ]"

play -e swap_size=''
check "no size set changes nothing" unchanged
check "and leaves the file at 384 MiB" state_is 384

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
