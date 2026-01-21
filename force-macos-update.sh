#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM
# Downloads run in background to avoid MDM timeout

LOG="/var/log/force-macos-update.log"
DOWNLOAD_LOG="/var/log/force-macos-update-download.log"

# Get current logged-in user
CURRENT_USER=$(stat -f "%Su" /dev/console)

# Function to log to both stdout (for Rippling) and log file
log() {
    echo "$1"
    echo "$1" >> "$LOG"
}

# Function to notify the user
notify_user() {
    local title="$1"
    local message="$2"
    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
        sudo -u "$CURRENT_USER" osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null
    fi
}

# Function to show alert dialog to user
show_alert() {
    local title="$1"
    local message="$2"
    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
        sudo -u "$CURRENT_USER" osascript -e "display dialog \"$message\" with title \"$title\" buttons {\"OK\"} default button \"OK\" giving up after 10" 2>/dev/null &
    fi
}

# Function to open System Settings
open_software_update() {
    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
        sudo -u "$CURRENT_USER" open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>/dev/null
    fi
}

log "=== Force macOS Update Started: $(date) ==="
log "[INFO] Current user: $CURRENT_USER"

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

    # Notify user that download is starting
    notify_user "macOS Update" "Downloading macOS upgrade. This may take 30-60 minutes. Please keep your Mac on and connected to the internet."

    # Show alert dialog so user definitely sees it
    show_alert "macOS Update Starting" "Your IT department is downloading a macOS upgrade to your computer.

This download will take 30-60 minutes. Please:
• Keep your Mac powered on
• Stay connected to the internet
• Do not shut down or restart

You will be notified when the download is complete."

    # Open System Settings to Software Update
    log "[INFO] Opening System Settings > Software Update for user visibility"
    open_software_update

    # Run the full installer download in background with nohup
    nohup bash -c '
        LOG="/var/log/force-macos-update-download.log"
        CURRENT_USER="'"$CURRENT_USER"'"

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
            INSTALLER_NAME=$(basename "$INSTALLER" .app)

            # Notify user download is complete
            if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
                sudo -u "$CURRENT_USER" osascript -e "display dialog \"macOS upgrade download complete!

The installer is ready in your Applications folder.

To upgrade:
1. Open Finder > Applications
2. Double-click '"'"'$INSTALLER_NAME'"'"'
3. Follow the on-screen instructions

Your Mac will restart during the upgrade.\" with title \"macOS Update Ready\" buttons {\"Open Applications\", \"Later\"} default button \"Open Applications\"" 2>/dev/null

                # If user clicks "Open Applications", open Finder to Applications
                if [ $? -eq 0 ]; then
                    sudo -u "$CURRENT_USER" open /Applications 2>/dev/null
                fi
            fi
        else
            echo "[ERROR] FAILED - No installer found in /Applications" >> "$LOG"
            echo "[ERROR] Check if there is enough disk space (~15-25GB required)" >> "$LOG"

            # Notify user of failure
            if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
                sudo -u "$CURRENT_USER" osascript -e "display notification \"Download failed. Please contact IT support.\" with title \"macOS Update Error\"" 2>/dev/null
            fi
        fi
    ' > /dev/null 2>&1 &

    BACKGROUND_PID=$!
    log "[OK] Background download started (PID: $BACKGROUND_PID)"
    log ""
    log "=== Script Complete: $(date) ==="
    log "[INFO] Download running in background - will continue after script exits"
    log "[INFO] User has been notified and System Settings opened"
    log "[INFO] Check download progress: cat $DOWNLOAD_LOG"
else
    log "[INFO] Incremental updates found!"
    log "[INFO] Starting background download..."

    # Notify user
    notify_user "macOS Update" "Downloading macOS updates. You will be notified when ready to install."

    # Open System Settings to Software Update so user can see progress
    log "[INFO] Opening System Settings > Software Update for user visibility"
    open_software_update

    # Run incremental update download in background
    nohup bash -c '
        LOG="/var/log/force-macos-update-download.log"
        CURRENT_USER="'"$CURRENT_USER"'"

        echo "=== Update Download Started: $(date) ===" > "$LOG"
        softwareupdate --download --all --force >> "$LOG" 2>&1
        EXIT_CODE=$?
        echo "" >> "$LOG"
        echo "=== Download Finished: $(date) ===" >> "$LOG"
        echo "[INFO] Exit code: $EXIT_CODE" >> "$LOG"

        # Notify user
        if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ]; then
            sudo -u "$CURRENT_USER" osascript -e "display dialog \"macOS updates are downloaded and ready to install.

Go to System Settings > General > Software Update to install.

Your Mac will restart during installation.\" with title \"macOS Update Ready\" buttons {\"Open Software Update\", \"Later\"} default button \"Open Software Update\"" 2>/dev/null

            if [ $? -eq 0 ]; then
                sudo -u "$CURRENT_USER" open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>/dev/null
            fi
        fi
    ' > /dev/null 2>&1 &

    BACKGROUND_PID=$!
    log "[OK] Background download started (PID: $BACKGROUND_PID)"
    log ""
    log "=== Script Complete: $(date) ==="
    log "[INFO] Updates downloading in background"
    log "[INFO] User has been notified and System Settings opened"
fi

log ""
log "=== Summary ==="
log "macOS Version: $CURRENT_VERSION"
log "Current User: $CURRENT_USER"
log "Main Log: $LOG"
log "Download Log: $DOWNLOAD_LOG"

exit 0
