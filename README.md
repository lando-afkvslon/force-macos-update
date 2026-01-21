# Force macOS Update

A script to force macOS to check for and download the latest OS updates, even when "No new software available" is incorrectly displayed.

## The Problem

macOS sometimes fails to detect available updates due to:
- Stale Software Update cache
- Corrupted catalog data
- Previously ignored updates
- DNS or connectivity caching issues

This results in "No new software available" even when newer macOS versions exist.

## What This Script Does

1. Clears all Software Update caches
2. Resets Software Update preferences
3. Removes any ignored updates
4. Restarts the `softwareupdated` daemon
5. Clears and refreshes the update catalog
6. Flushes DNS cache
7. Forces a fresh check for updates
8. **Downloads all available updates** (does NOT auto-install)
9. Logs all actions to `/var/log/force-macos-update.log`

## Usage

### For Rippling MDM (Recommended)

**Option 1: Download and execute**
```bash
cd /tmp && curl -fsSO https://raw.githubusercontent.com/lando-afkvslon/force-macos-update/main/force-macos-update.sh && /bin/bash force-macos-update.sh && rm force-macos-update.sh
```

**Option 2: One-liner with pipe**
```bash
curl -fsSL https://raw.githubusercontent.com/lando-afkvslon/force-macos-update/main/force-macos-update.sh | /bin/bash
```

### Manual Download and Run

```bash
curl -O https://raw.githubusercontent.com/lando-afkvslon/force-macos-update/main/force-macos-update.sh
chmod +x force-macos-update.sh
sudo ./force-macos-update.sh
```

## Requirements

- macOS 10.15 (Catalina) or later
- Administrator/root privileges
- Internet connection

## Log File

All output is logged to:
```
/var/log/force-macos-update.log
```

View logs with:
```bash
cat /var/log/force-macos-update.log
```

## After Running

1. The script downloads updates but does **not** install them automatically
2. User opens **System Settings > General > Software Update**
3. The update should appear ready to install
4. User clicks "Install" to complete the update

## Notes

- Download time depends on update size and connection speed
- Large updates (e.g., major macOS versions) may take 20-60 minutes to download
- The Mac will **not** restart automatically - user must initiate install

## License

MIT License - Use at your own risk.
