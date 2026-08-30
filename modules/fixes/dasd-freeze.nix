# Freeze dasd when it busy-loops (macOS 27 bug: dasd spins a core at ~100%
# via kevent_qos busy-wait with no log/task/IO activity; SIP blocks
# kickstart, deleting its DB doesn't help, and it survives reboot).
#
# The fix: a user LaunchAgent that, at login and every 60s, checks whether
# dasd is actually busy-looping (CPU > 50% sustained) and only then SIGSTOPs
# it. If Apple ever fixes the bug (dasd idles normally), the check simply
# won't fire and dasd runs untouched. SIGSTOP is reversible (SIGCONT).
#
# Verified 2026-08-30: dasd at 100% with zero logs/IO/tasks; after
# `kill -STOP`, CPU 0%, system stable, no errors (see nb home/11).
{
  config,
  lib,
  pkgs,
  ...
}: let
  freezeScript = pkgs.writeShellScript "dasd-freeze" ''
    set -u
    # Leave dasd alone for the first 60s after login (system still settling,
    # dasd legitimately busy scheduling startup tasks).
    boottime=$(/usr/sbin/sysctl -n kern.boottime 2>/dev/null | /usr/bin/tr -dc '0-9 ' | /usr/bin/awk '{print $1}')
    now=$(/bin/date +%s)
    if [ -n "$boottime" ] && [ $((now - boottime)) -lt 60 ]; then
      exit 0
    fi

    DASD_PID=$(/usr/bin/pgrep -x dasd 2>/dev/null || true)
    [ -z "$DASD_PID" ] && exit 0

    # Skip if already stopped (T state).
    state=$(/bin/ps -o stat= -p "$DASD_PID" 2>/dev/null || true)
    case "$state" in
      T*) exit 0 ;;
    esac

    # Sample CPU twice, 1s apart; only freeze if consistently > 50%.
    cpu1=$(/bin/ps -o %cpu= -p "$DASD_PID" 2>/dev/null | /usr/bin/tr -d ' ' || echo 0)
    sleep 1
    cpu2=$(/bin/ps -o %cpu= -p "$DASD_PID" 2>/dev/null | /usr/bin/tr -d ' ' || echo 0)
    busy=$(/usr/bin/awk -v a="$cpu1" -v b="$cpu2" 'BEGIN { print (a>50 && b>50) ? 1 : 0 }')

    if [ "$busy" = "1" ]; then
      /bin/kill -STOP "$DASD_PID" 2>/dev/null || true
      /usr/bin/logger -t dasd-freeze "dasd busy-looping (cpu $cpu1/$cpu2) -> SIGSTOP $DASD_PID"
    fi
  '';
in {
  launchd.user.agents.dasd-freeze = {
    serviceConfig = {
      ProgramArguments = [ "${freezeScript}" ];
      StartInterval = 60;
      RunAtLoad = true;
      ProcessType = "Background";
    };
  };
}
