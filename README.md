# Force macOS Update Script

A script to force macOS devices to download and prepare the latest OS update (e.g., Sequoia → Tahoe), designed for deployment via Rippling MDM.

## Quick Reference

### Rippling Command
```bash
cd /tmp && curl -fsSO https://raw.githubusercontent.com/lando-afkvslon/force-macos-update/main/force-macos-update.sh && /bin/bash force-macos-update.sh && rm force-macos-update.sh
```

### GitHub Repository
https://github.com/lando-afkvslon/force-macos-update

## What This Script Does

1. **Removes update blockers** - Clears deferral settings, restrictions, and resets update preferences
2. **Clears update caches** - Removes stale update data that can cause "no updates available"
3. **Restarts update daemon** - Refreshes the softwareupdated service
4. **Lists available installers** - Shows all macOS versions available from Apple
5. **Downloads latest non-deferred version** - Gets the newest macOS that isn't being held back
6. **Shows progress to user** - Opens a Terminal window with live download progress
7. **Prevents sleep** - Uses caffeinate to keep Mac awake during download
8. **Notifies user when done** - Shows dialog with instructions to install

## Log Files (on target Mac)

| Log | Purpose |
|-----|---------|
| `/var/log/force-macos-update.log` | Main script output |
| `/var/log/force-macos-update-download.log` | Download progress and status |
| `/var/log/force-macos-update-daemon.log` | LaunchDaemon output |

### View logs on Mac:
```bash
cat /var/log/force-macos-update.log
cat /var/log/force-macos-update-download.log
```

### Watch download progress live:
```bash
tail -f /var/log/force-macos-update-download.log
```

## After Download Completes

The installer will be in `/Applications/Install macOS Tahoe.app`

**User needs to:**
1. Open Finder → Applications
2. Double-click "Install macOS Tahoe"
3. Follow prompts (Mac will restart)

**Note:** If user doesn't have admin rights, they'll need IT to provide admin credentials to run the installer.

## Troubleshooting

### "No new software available"
- Script handles this by using `--fetch-full-installer` instead
- Check download log for available versions

### "Update not available" / "Deferred: YES"
- Apple is holding back that version
- Script automatically picks latest non-deferred version

### Terminal window doesn't open
- Check if LaunchAgent loaded: `launchctl list | grep force-macos`
- Progress still works in background, check download log

### Download stuck
- Check if caffeinate is running: `ps aux | grep caffeinate`
- Check download log for progress percentage
- Large downloads (~16GB) take 30-60 minutes

### Permission errors (-1743)
- Fixed in latest version using LaunchAgent instead of AppleScript

## Modifying the Script

### To target a specific macOS version:

Edit `force-macos-update.sh` and find this section:
```bash
# Get the highest version that is NOT deferred (Deferred: NO)
LATEST_VERSION=$(echo "$INSTALLER_LIST" | grep "Deferred: NO" | grep -o 'Version: [0-9.]*' | head -1 | awk '{print $2}')
```

Replace with a hardcoded version:
```bash
LATEST_VERSION="26.1"
```

Then commit and push:
```bash
git add -A && git commit -m "Target specific version" && git push
```

### To see available versions:
Run on any Mac:
```bash
softwareupdate --list-full-installers
```

## File Structure

```
/Users/orlando/force-macos-update/
├── README.md                 # This file
├── force-macos-update.sh     # Main script
├── QUICK-REFERENCE.md        # One-page cheat sheet
└── .git/                     # Git repo (synced to GitHub)
```

## Version History

- **Jan 2026** - Initial release
  - Supports Sequoia → Tahoe upgrade
  - Handles deferred versions
  - Terminal progress window
  - LaunchDaemon for persistent download
  - Caffeinate to prevent sleep

## Contact

For issues: https://github.com/lando-afkvslon/force-macos-update/issues
