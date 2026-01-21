#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM

LOG="/var/log/force-macos-update.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Force macOS Update Started: $(date) ==="

# Get current macOS version
CURRENT_VERSION=$(sw_vers -productVersion)
CURRENT_MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
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

# --- DOWNLOAD UPDATES OR FETCH FULL INSTALLER ---
if echo "$AVAILABLE" | grep -q "No new software available"; then
    echo "[INFO] No incremental updates found"
    echo "[INFO] Attempting to fetch latest full macOS installer..."
    echo "[INFO] This is required for major version upgrades (e.g., Sequoia → Tahoe)"
    echo ""

    # Fetch the latest available full installer
    # This downloads the complete macOS installer to /Applications
    echo "[INFO] Downloading full macOS installer (this may take 30-60 minutes)..."
    softwareupdate --fetch-full-installer 2>&1

    # Check if installer was downloaded
    INSTALLER=$(ls -d /Applications/Install\ macOS*.app 2>/dev/null | head -1)
    if [ -n "$INSTALLER" ]; then
        echo ""
        echo "[OK] Full installer downloaded successfully!"
        echo "[INFO] Installer location: $INSTALLER"
        echo ""
        echo "[INFO] To install, user can either:"
        echo "       1. Open the installer app in /Applications"
        echo "       2. Or run: sudo \"$INSTALLER/Contents/Resources/startosinstall\" --agreetolicense"
    else
        echo ""
        echo "[WARN] Could not verify installer download"
        echo "[INFO] Check /Applications for 'Install macOS' app"
    fi
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
echo "[INFO] Or open the installer in /Applications if a full installer was downloaded"
