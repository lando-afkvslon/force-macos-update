#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM
# Downloads run in background to avoid MDM timeout

LOG="/var/log/force-macos-update.log"
DOWNLOAD_LOG="/var/log/force-macos-update-download.log"

echo "=== Force macOS Update Started: $(date) ===" >> "$LOG"

# Get current macOS version
CURRENT_VERSION=$(sw_vers -productVersion)
echo "[INFO] Current macOS version: $CURRENT_VERSION" >> "$LOG"

# --- CLEAR ALL UPDATE CACHES ---
echo "[INFO] Clearing Software Update caches..." >> "$LOG"
rm -rf /Library/Updates/* 2>/dev/null || true
rm -rf /var/folders/*/*/*/com.apple.SoftwareUpdate* 2>/dev/null || true
rm -f /var/db/softwareupdate/journal.plist 2>/dev/null || true
rm -rf /var/db/softwareupdate/SoftwareUpdateAvailable.plist 2>/dev/null || true

# --- RESET PREFERENCES ---
echo "[INFO] Resetting Software Update preferences..." >> "$LOG"
defaults delete /Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null || true
defaults delete /var/root/Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null || true

# --- RESET IGNORED UPDATES ---
echo "[INFO] Resetting any ignored updates..." >> "$LOG"
softwareupdate --reset-ignored 2>/dev/null || true

# --- RESTART SOFTWARE UPDATE DAEMON ---
echo "[INFO] Restarting Software Update daemon..." >> "$LOG"
launchctl kickstart -k system/com.apple.softwareupdated 2>/dev/null || killall softwareupdated 2>/dev/null || true
sleep 3

# --- CLEAR AND REFRESH CATALOG ---
echo "[INFO] Clearing Software Update catalog..." >> "$LOG"
softwareupdate --clear-catalog 2>&1 >> "$LOG" || true

# --- FLUSH DNS ---
echo "[INFO] Flushing DNS cache..." >> "$LOG"
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true

# --- FORCE CHECK FOR UPDATES ---
echo "[INFO] Forcing check for available updates..." >> "$LOG"
AVAILABLE=$(softwareupdate -l 2>&1)
echo "$AVAILABLE" >> "$LOG"

# --- DOWNLOAD UPDATES OR FETCH FULL INSTALLER (IN BACKGROUND) ---
if echo "$AVAILABLE" | grep -q "No new software available"; then
    echo "[INFO] No incremental updates found" >> "$LOG"
    echo "[INFO] Starting background download of full macOS installer..." >> "$LOG"
    echo "[INFO] Download progress will be logged to: $DOWNLOAD_LOG" >> "$LOG"

    # Run the full installer download in background with nohup
    # This prevents Rippling timeout while download continues
    nohup bash -c '
        LOG="/var/log/force-macos-update-download.log"
        echo "=== Full Installer Download Started: $(date) ===" > "$LOG"
        echo "[INFO] Downloading latest macOS installer (this may take 30-60 minutes)..." >> "$LOG"

        softwareupdate --fetch-full-installer >> "$LOG" 2>&1

        echo "" >> "$LOG"
        echo "=== Download Complete: $(date) ===" >> "$LOG"

        # Check if installer was downloaded
        INSTALLER=$(ls -d /Applications/Install\ macOS*.app 2>/dev/null | head -1)
        if [ -n "$INSTALLER" ]; then
            echo "[OK] Installer downloaded: $INSTALLER" >> "$LOG"

            # Create a notification for the user
            CURRENT_USER=$(stat -f "%Su" /dev/console)
            if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
                sudo -u "$CURRENT_USER" osascript -e "display notification \"macOS upgrade is ready to install. Open the installer in Applications.\" with title \"macOS Update Ready\""
            fi
        else
            echo "[WARN] Could not verify installer download" >> "$LOG"
        fi
    ' > /dev/null 2>&1 &

    echo "[OK] Background download started - script exiting to avoid MDM timeout" >> "$LOG"
    echo "[INFO] Check $DOWNLOAD_LOG for download progress" >> "$LOG"
else
    echo "[INFO] Updates found! Starting background download..." >> "$LOG"

    # Run incremental update download in background
    nohup bash -c '
        LOG="/var/log/force-macos-update-download.log"
        echo "=== Update Download Started: $(date) ===" > "$LOG"
        softwareupdate --download --all --force >> "$LOG" 2>&1
        echo "=== Download Complete: $(date) ===" >> "$LOG"

        # Notify user
        CURRENT_USER=$(stat -f "%Su" /dev/console)
        if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
            sudo -u "$CURRENT_USER" osascript -e "display notification \"macOS updates are ready to install in System Settings.\" with title \"macOS Update Ready\""
        fi
    ' > /dev/null 2>&1 &

    echo "[OK] Background download started" >> "$LOG"
fi

# --- FINAL STATUS ---
echo "" >> "$LOG"
echo "=== Script Complete: $(date) ===" >> "$LOG"
echo "[INFO] Download running in background" >> "$LOG"
echo "[INFO] Main log: $LOG" >> "$LOG"
echo "[INFO] Download log: $DOWNLOAD_LOG" >> "$LOG"

# Exit successfully so Rippling sees completion
exit 0
