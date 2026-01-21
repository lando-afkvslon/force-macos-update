# Force macOS Update

A script to force macOS to check for and download the latest OS updates, including **major version upgrades** (e.g., Sequoia → Tahoe).

## The Problem

macOS sometimes fails to detect available updates due to:
- Stale Software Update cache
- Corrupted catalog data
- Previously ignored updates
- Major version upgrades not appearing in normal update checks
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
8. If no incremental updates found, **downloads the full macOS installer** using `--fetch-full-installer`
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
- Sufficient disk space (~15-25GB for full installer)

## After Running

### If incremental updates were found:
1. Updates are downloaded but **not** installed automatically
2. User opens **System Settings > General > Software Update**
3. Click "Install" to complete the update

### If full installer was downloaded (major version upgrade):
1. The installer app appears in `/Applications` (e.g., "Install macOS Tahoe.app")
2. User can either:
   - Open the installer app directly
   - Or the script provides a command to start installation

## Notes

- **Downloads run in background** to avoid MDM timeout - script returns immediately
- Full installer download may take 30-60 minutes depending on connection speed
- Full installers require ~15-25GB of free disk space
- The Mac will **not** restart automatically - user must initiate install
- For major version upgrades, the full installer method is more reliable than waiting for Software Update
- User gets a macOS notification when download completes

## Log Files

- Main log: `/var/log/force-macos-update.log`
- Download progress: `/var/log/force-macos-update-download.log`

## License

MIT License - Use at your own risk.
