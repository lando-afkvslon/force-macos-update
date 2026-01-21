#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Fixes "No updates available" when updates actually exist
# For deployment via Rippling MDM

LOG="/var/log/force-macos-update.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Force macOS Update Started: $(date) ==="

# Get current macOS version
CURRENT_VERSION=$(sw_vers -productVersion)
echo "[INFO] Current macOS version: $CURRENT_VERSION"

# --- CLEAR ALL UPDATE CACHES ---
echo "[INFO] Clearing Software Update caches..."
rm -rf /Library/Updates/* 2>/dev/null || true
rm -rf /var/folders/*/*/*/com.apple.SoftwareUpdate* 2>/dev/null || true
rm -f /var/db/softwareupdate/journal.plist 2>/dev/null || true
rm -rf /var/db/softwareupdate/SoftwareUpdateAvailable.plist 2>/dev/null || true

# --- RESET PREFERENCES ---
echo "[INFO] Resetting Software Update preferences..."
defaults delete /Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null || true
defaults delete /var/root/Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null || true

# --- RESET IGNORED UPDATES ---
echo "[INFO] Resetting any ignored updates..."
softwareupdate --reset-ignored 2>/dev/null || true

# --- RESTART SOFTWARE UPDATE DAEMON ---
echo "[INFO] Restarting Software Update daemon..."
launchctl kickstart -k system/com.apple.softwareupdated 2>/dev/null || killall softwareupdated 2>/dev/null || true
sleep 3

# --- CLEAR AND REFRESH CATALOG ---
echo "[INFO] Clearing Software Update catalog..."
softwareupdate --clear-catalog 2>&1 || true

# --- FLUSH DNS (helps with connectivity issues) ---
echo "[INFO] Flushing DNS cache..."
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

# --- FORCE CHECK FOR UPDATES ---
echo "[INFO] Forcing check for available updates..."
echo ""
AVAILABLE=$(softwareupdate -l 2>&1)
echo "$AVAILABLE"
echo ""

# --- DOWNLOAD UPDATES ---
if echo "$AVAILABLE" | grep -q "No new software available"; then
    echo "[INFO] No updates found after refresh"
    echo "[INFO] This Mac may already be on the latest version"
else
    echo "[INFO] Updates found! Starting download..."
    echo "[INFO] This may take a while depending on update size and connection speed"
    echo ""

    # Download all available updates (will not install or restart)
    softwareupdate --download --all --force 2>&1

    echo ""
    echo "[OK] Download complete!"
    echo "[INFO] Updates are ready to install"
fi

# --- FINAL STATUS ---
echo ""
echo "=== Final Status ==="
echo "[INFO] Current macOS: $CURRENT_VERSION"
echo "[INFO] Log saved to: $LOG"
echo ""
echo "=== Force Update Complete: $(date) ==="
echo "[INFO] User can now install via System Settings > General > Software Update"
