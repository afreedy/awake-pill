# Awake Pill

A native floating glass pill and menu bar toggle for macOS. Requires Apple Silicon, macOS 26 or newer and Xcode Command Line Tools. No network calls, accounts, deployment, or dependencies.

Click **Keep awake with lid closed**, then approve macOS's administrator dialog. It runs exactly `/usr/bin/pmset -a disablesleep 1` and reads the kernel's `SleepDisabled` property before showing success. **Allow sleep again** runs the same command with `0`. Normal Quit restores sleep before exiting; cancelled/failed restoration keeps the app open.

This is a global system setting, not a per-app guarantee. It prevents sleep, including manual sleep, but cannot prevent individual apps from suspending work, crashing, network interruptions, shutdown or battery exhaustion. Keep the Mac ventilated; never leave it running in a closed bag. The display can still turn off. Physical lid-close behavior requires a test on your Mac.

Force quit/crashes cannot restore the privileged setting. Reopen Awake Pill and click **Allow sleep again**, or recover in Terminal with `sudo pmset -a disablesleep 0`. The app rereads the actual setting on launch and does not enable it automatically. No timer or low-battery cutoff is installed.

Install after building: `mkdir -p ~/Applications && ditto AwakePill.app ~/Applications/AwakePill.app`, then open `~/Applications/AwakePill.app`.

Startup: `./startup.sh on` installs a root-owned LaunchDaemon that runs only `/usr/bin/pmset -a disablesleep 1` once per boot, and a user LaunchAgent that opens the pill at login. One administrator approval installs it; subsequent boots need no prompt. It also enables keep-awake immediately. Normal Quit or **Allow sleep again** restores sleep for the current session; startup enables it again next boot. `./startup.sh off` removes both startup entries without changing the current sleep setting. Files: `/Library/LaunchDaemons/com.afreed.awakepill.boot.plist` and `~/Library/LaunchAgents/com.afreed.awakepill.plist`. No repeating job or passwordless permission grant is installed.

Build: `zsh build.sh`. Runnable non-mutating check: `AwakePill.app/Contents/MacOS/AwakePill --check`.

Installed app: `~/Applications/AwakePill.app`. Source: this folder. Drag the header to reposition; menu bar offers show/hide, toggle, and Quit.

Feasibility reference: https://github.com/Aboudjem/Sleepless documents the same `pmset` mechanism, with hardware/macOS-dependent behavior. This app uses its own small implementation and macOS's built-in administrator prompt; no sudoers grant.
