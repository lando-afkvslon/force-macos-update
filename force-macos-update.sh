#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM
# Downloads run in background to avoid MDM timeout

LOG="/var/log/force-macos-update.log"
DOWNLOAD_LOG="/var/log/force-macos-update-download.log"

# Function to log to both stdout (for Rippling) and log file
log() {
    echo "$1"
    echo "$1" >> "$LOG"
}

log "=== Force macOS Update Started: $(date) ==="

# Get current macOS version
CURRENT_VERSION=$(sw_vers -productVersion)
log "[INFO] Current macOS version: $CURRENT_VERSION"

# --- CLEAR ALL UPDATE CACHES ---
log "[INFO] Clearing Software Update caches..."
rm -rf /Library/Updates/* 2>/dev/null || true
rm -rf /var/folders/*/*/*/com.apple.SoftwareUpdate* 2>/dev/null || true
rm -f /var/db/softwareupdate/journal.plist 2>/dev/null || true
rm -rf /var/db/softwareupdate/SoftwareUpdateAvailable.plist 2>/dev/null || true
log "[OK] Caches cleared"

# --- RESET PREFERENCES ---
log "[INFO] Resetting Software Update preferences..."
defaults delete /Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null || true
defaults delete /var/root/Library/Preferences/com.apple.SoftwareUpdate 2>/dev/null || true
log "[OK] Preferences reset"

# --- RESET IGNORED UPDATES ---
log "[INFO] Resetting any ignored updates..."
softwareupdate --reset-ignored 2>/dev/null || true
log "[OK] Ignored updates reset"

# --- RESTART SOFTWARE UPDATE DAEMON ---
log "[INFO] Restarting Software Update daemon..."
launchctl kickstart -k system/com.apple.softwareupdated 2>/dev/null || killall softwareupdated 2>/dev/null || true
sleep 3
log "[OK] Daemon restarted"

# --- CLEAR AND REFRESH CATALOG ---
log "[INFO] Clearing Software Update catalog..."
CATALOG_RESULT=$(softwareupdate --clear-catalog 2>&1)
log "$CATALOG_RESULT"
log "[OK] Catalog cleared"

# --- FLUSH DNS ---
log "[INFO] Flushing DNS cache..."
dscacheutil -flushcache 2>/dev/null || true
killall -HUP mDNSResponder 2>/dev/null || true
log "[OK] DNS flushed"

# --- FORCE CHECK FOR UPDATES ---
log "[INFO] Checking for available updates..."
AVAILABLE=$(softwareupdate -l 2>&1)
log ""
log "$AVAILABLE"
log ""

# --- DOWNLOAD UPDATES OR FETCH FULL INSTALLER (IN BACKGROUND) ---
if echo "$AVAILABLE" | grep -q "No new software available"; then
    log "[INFO] No incremental updates found via softwareupdate -l"
    log "[INFO] Will attempt to fetch full macOS installer for major version upgrade"
    log "[INFO] Starting background download of full macOS installer..."
    log "[INFO] Download progress logged to: $DOWNLOAD_LOG"
    log "[INFO] Download will take 30-60 minutes depending on connection speed"

    # Run the full installer download in background with nohup
    nohup bash -c '
        LOG="/var/log/force-macos-update-download.log"
        echo "=== Full Installer Download Started: $(date) ===" > "$LOG"
        echo "[INFO] Downloading latest macOS installer..." >> "$LOG"

        softwareupdate --fetch-full-installer >> "$LOG" 2>&1
        EXIT_CODE=$?

        echo "" >> "$LOG"
        echo "=== Download Finished: $(date) ===" >> "$LOG"
        echo "[INFO] Exit code: $EXIT_CODE" >> "$LOG"

        # Check if installer was downloaded
        INSTALLER=$(ls -d /Applications/Install\ macOS*.app 2>/dev/null | head -1)
        if [ -n "$INSTALLER" ]; then
            echo "[OK] SUCCESS - Installer downloaded: $INSTALLER" >> "$LOG"

            # Create a notification for the user
            CURRENT_USER=$(stat -f "%Su" /dev/console)
            if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
                sudo -u "$CURRENT_USER" osascript -e "display notification \"macOS upgrade is ready to install. Open the installer in Applications.\" with title \"macOS Update Ready\"" 2>/dev/null
            fi
        else
            echo "[ERROR] FAILED - No installer found in /Applications" >> "$LOG"
            echo "[ERROR] Check if there is enough disk space (~15-25GB required)" >> "$LOG"
        fi
    ' > /dev/null 2>&1 &

    BACKGROUND_PID=$!
    log "[OK] Background download started (PID: $BACKGROUND_PID)"
    log ""
    log "=== Script Complete: $(date) ==="
    log "[INFO] Download running in background - will continue after script exits"
    log "[INFO] User will receive notification when download completes"
    log "[INFO] Check download progress: cat $DOWNLOAD_LOG"
else
    log "[INFO] Incremental updates found!"
    log "[INFO] Starting background download..."

    # Run incremental update download in background
    nohup bash -c '
        LOG="/var/log/force-macos-update-download.log"
        echo "=== Update Download Started: $(date) ===" > "$LOG"
        softwareupdate --download --all --force >> "$LOG" 2>&1
        EXIT_CODE=$?
        echo "" >> "$LOG"
        echo "=== Download Finished: $(date) ===" >> "$LOG"
        echo "[INFO] Exit code: $EXIT_CODE" >> "$LOG"

        # Notify user
        CURRENT_USER=$(stat -f "%Su" /dev/console)
        if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
            sudo -u "$CURRENT_USER" osascript -e "display notification \"macOS updates are ready to install in System Settings.\" with title \"macOS Update Ready\"" 2>/dev/null
        fi
    ' > /dev/null 2>&1 &

    BACKGROUND_PID=$!
    log "[OK] Background download started (PID: $BACKGROUND_PID)"
    log ""
    log "=== Script Complete: $(date) ==="
    log "[INFO] Updates downloading in background"
    log "[INFO] User will receive notification when ready"
fi

log ""
log "=== Summary ==="
log "macOS Version: $CURRENT_VERSION"
log "Main Log: $LOG"
log "Download Log: $DOWNLOAD_LOG"

exit 0
