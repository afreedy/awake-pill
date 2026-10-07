#!/bin/zsh
set -eu
cd "${0:A:h}"
case "${1:-on}" in
  on)
    # Embed the exact plist into the authorized command, rather than running a user-writable helper as root.
    app_path="$HOME/Applications/AwakePill.app"
    [[ -d "$app_path" ]] || { print -u2 "Install AwakePill.app into ~/Applications first."; exit 1; }
    /usr/bin/plutil -lint Startup.plist Login.plist
    startup_payload=$(/usr/bin/base64 -i Startup.plist | /usr/bin/tr -d '\n')
    startup_command="/bin/mkdir -p /Library/LaunchDaemons && /usr/bin/printf '%s' '$startup_payload' | /usr/bin/base64 -D > /Library/LaunchDaemons/com.afreed.awakepill.boot.plist && /usr/sbin/chown root:wheel /Library/LaunchDaemons/com.afreed.awakepill.boot.plist && /bin/chmod 644 /Library/LaunchDaemons/com.afreed.awakepill.boot.plist && (/bin/launchctl print system/com.afreed.awakepill.boot >/dev/null 2>&1 || /bin/launchctl bootstrap system /Library/LaunchDaemons/com.afreed.awakepill.boot.plist) && /usr/bin/pmset -a disablesleep 1"
    ;;
  off)
    startup_command="(/bin/launchctl print system/com.afreed.awakepill.boot >/dev/null 2>&1 && /bin/launchctl bootout system/com.afreed.awakepill.boot || /usr/bin/true) && /bin/rm -f /Library/LaunchDaemons/com.afreed.awakepill.boot.plist"
    ;;
  *) print -u2 'Usage: startup.sh on|off'; exit 2 ;;
esac
/usr/bin/osascript - "$startup_command" <<'APPLESCRIPT'
on run arguments
    do shell script (item 1 of arguments) with administrator privileges
end run
APPLESCRIPT
if [[ "${1:-on}" == on ]]; then
  /bin/mkdir -p "$HOME/Library/LaunchAgents"
  login_agent="$HOME/Library/LaunchAgents/com.afreed.awakepill.plist"
  /bin/cp Login.plist "$login_agent"
  /usr/bin/plutil -replace ProgramArguments.2 -string "$app_path" "$login_agent"
  /bin/launchctl print "gui/$UID/com.afreed.awakepill" >/dev/null 2>&1 || /bin/launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/com.afreed.awakepill.plist"
  /bin/launchctl print system/com.afreed.awakepill.boot
  print 'Startup enabled. Awake Pill enables keep-awake at boot and opens at login.'
else
  if /bin/launchctl print "gui/$UID/com.afreed.awakepill" >/dev/null 2>&1; then
    /bin/launchctl bootout "gui/$UID/com.afreed.awakepill"
  fi
  /bin/rm -f "$HOME/Library/LaunchAgents/com.afreed.awakepill.plist"
  print 'Startup disabled. Current sleep setting unchanged; use the pill to allow sleep.'
fi
