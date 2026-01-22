# Force macOS Update - Session Context

## Project Summary
A bash script deployed via Rippling MDM that forces macOS devices to download the latest OS update (e.g., Sequoia 15.x → Tahoe 26.x) when normal Software Update shows "no updates available".

## Key Details

- **GitHub Repo:** https://github.com/lando-afkvslon/force-macos-update
- **Local Path:** `/Users/orlando/force-macos-update/`
- **Main Script:** `force-macos-update.sh`
- **Deployed via:** Rippling MDM

## Rippling Command
```bash
cd /tmp && curl -fsSO https://raw.githubusercontent.com/lando-afkvslon/force-macos-update/main/force-macos-update.sh && /bin/bash force-macos-update.sh && rm force-macos-update.sh
```

## What the Script Does

1. Runs as root via MDM
2. Removes update blockers/deferral settings
3. Clears Software Update caches
4. Restarts softwareupdated daemon
5. Lists available installers via `softwareupdate --list-full-installers`
6. Downloads latest **non-deferred** version via `softwareupdate --fetch-full-installer --full-installer-version X.X`
7. Opens Terminal window showing live download progress (via LaunchAgent)
8. Uses caffeinate to prevent sleep during download
9. Shows completion dialog when done
10. Installer lands in `/Applications/Install macOS [Name].app`

## Technical Solutions Implemented

| Problem | Solution |
|---------|----------|
| MDM script timeout | LaunchDaemon runs download in background |
| GUI from root context | LaunchAgent opens Terminal (not osascript) |
| "No updates available" | Uses `--fetch-full-installer` instead |
| Downloaded wrong version | Filters for `Deferred: NO` versions |
| User can't see progress | Terminal window with `tail -f` on log |
| Mac sleeps during download | caffeinate keeps it awake |
| Automation permission error (-1743) | LaunchAgent instead of AppleScript |

## Log Files (on target Mac)
- `/var/log/force-macos-update.log` - Main script
- `/var/log/force-macos-update-download.log` - Download progress
- `/var/log/force-macos-update-daemon.log` - LaunchDaemon output

## To Modify

1. Edit `/Users/orlando/force-macos-update/force-macos-update.sh`
2. Commit and push: `git add -A && git commit -m "change" && git push`

### Target specific version:
Find `LATEST_VERSION=...` line and replace with:
```bash
LATEST_VERSION="26.1"
```

## Created
January 2026
