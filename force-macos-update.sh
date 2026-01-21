#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM
# Uses LaunchDaemon for persistent background download

LOG="/var/log/force-macos-update.log"
DOWNLOAD_LOG="/var/log/force-macos-update-download.log"
DOWNLOAD_SCRIPT="/usr/local/bin/force-macos-update-download.sh"
LAUNCHDAEMON_PLIST="/Library/LaunchDaemons/com.force-macos-update.download.plist"

# Get current logged-in user
CURRENT_USER=$(stat -f "%Su" /dev/console)

# Function to log to both stdout (for Rippling) and log file
log() {
    echo "$1"
    echo "$1" >> "$LOG"
}

log "=== Force macOS Update Started: $(date) ==="
log "[INFO] Current user: $CURRENT_USER"

# Get current macOS version
CURRENT_VERSION=$(sw_vers -productVersion)
log "[INFO] Current macOS version: $CURRENT_VERSION"

# --- REMOVE UPDATE BLOCKERS AND RESTRICTIONS ---
log "[INFO] Checking for update blockers and restrictions..."

# List current profiles
log "[INFO] Current configuration profiles:"
PROFILES=$(profiles list 2>&1)
log "$PROFILES"

# Remove deferral settings
log "[INFO] Removing update deferral settings..."
defaults delete /Library/Preferences/com.apple.applicationaccess forceDelayedSoftwareUpdates 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.applicationaccess enforcedSoftwareUpdateDelay 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.applicationaccess forceDelayedMajorSoftwareUpdates 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.applicationaccess enforcedSoftwareUpdateMajorOSDeferredInstallDelay 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.applicationaccess forceDelayedAppSoftwareUpdates 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.applicationaccess enforcedSoftwareUpdateMinorOSDeferredInstallDelay 2>/dev/null || true
log "[OK] Deferral settings cleared"

# Remove restrictions on major OS upgrades
log "[INFO] Removing major OS upgrade restrictions..."
defaults delete /Library/Preferences/com.apple.applicationaccess restrictOSUpdatesToAdminUsers 2>/dev/null || true
defaults write /Library/Preferences/com.apple.applicationaccess allowMajorOSUpgrade -bool true 2>/dev/null || true

# Remove Software Update restrictions
log "[INFO] Removing Software Update restrictions..."
defaults delete /Library/Preferences/com.apple.SoftwareUpdate RestrictSoftwareUpdateRequireAdminToInstall 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.SoftwareUpdate ManagedInstalls 2>/dev/null || true
defaults delete /Library/Preferences/com.apple.SoftwareUpdate CatalogURL 2>/dev/null || true

# Enable automatic updates
log "[INFO] Enabling automatic update checks..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null || true
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true 2>/dev/null || true

log "[OK] Update blockers check complete"

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

# --- CREATE DOWNLOAD SCRIPT ---
log "[INFO] Creating persistent download script..."

mkdir -p /usr/local/bin

cat > "$DOWNLOAD_SCRIPT" << 'DOWNLOADSCRIPT'
#!/bin/bash
LOG="/var/log/force-macos-update-download.log"
CURRENT_USER=$(stat -f "%Su" /dev/console)

echo "=== macOS Update Download Started: $(date) ===" > "$LOG"
echo "[INFO] Running as: $(whoami)" >> "$LOG"
echo "[INFO] Current console user: $CURRENT_USER" >> "$LOG"

# Send notification to user that download is starting
if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ]; then
    sudo -u "$CURRENT_USER" osascript -e 'display notification "Downloading macOS upgrade. This may take 30-60 minutes." with title "macOS Update"' 2>/dev/null

    # Open System Settings
    sudo -u "$CURRENT_USER" open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>/dev/null
fi

# Check for incremental updates first
echo "[INFO] Checking for updates..." >> "$LOG"
AVAILABLE=$(softwareupdate -l 2>&1)
echo "$AVAILABLE" >> "$LOG"

if echo "$AVAILABLE" | grep -q "No new software available"; then
    echo "[INFO] No incremental updates - downloading full installer..." >> "$LOG"

    # Download full installer
    echo "[INFO] Starting softwareupdate --fetch-full-installer..." >> "$LOG"
    softwareupdate --fetch-full-installer 2>&1 | tee -a "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}
    echo "[INFO] softwareupdate exit code: $EXIT_CODE" >> "$LOG"
else
    echo "[INFO] Incremental updates found - downloading..." >> "$LOG"
    softwareupdate --download --all --force 2>&1 | tee -a "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}
    echo "[INFO] softwareupdate exit code: $EXIT_CODE" >> "$LOG"
fi

echo "" >> "$LOG"
echo "=== Download Finished: $(date) ===" >> "$LOG"

# Check results and notify user
INSTALLER=$(ls -d /Applications/Install\ macOS*.app 2>/dev/null | head -1)

if [ -n "$INSTALLER" ]; then
    INSTALLER_NAME=$(basename "$INSTALLER" .app)
    echo "[OK] SUCCESS - Found installer: $INSTALLER" >> "$LOG"

    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ]; then
        sudo -u "$CURRENT_USER" osascript -e "display dialog \"macOS upgrade is ready!

Open the installer in your Applications folder:
$INSTALLER_NAME

Your Mac will restart during the upgrade.\" with title \"macOS Update Ready\" buttons {\"Open Applications\", \"Later\"} default button \"Open Applications\"" 2>/dev/null

        if [ $? -eq 0 ]; then
            sudo -u "$CURRENT_USER" open /Applications 2>/dev/null
        fi
    fi
elif [ $EXIT_CODE -eq 0 ]; then
    echo "[OK] Updates downloaded successfully" >> "$LOG"

    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ]; then
        sudo -u "$CURRENT_USER" osascript -e 'display dialog "macOS updates are ready to install.

Go to System Settings > General > Software Update" with title "macOS Update Ready" buttons {"Open Settings", "Later"} default button "Open Settings"' 2>/dev/null

        if [ $? -eq 0 ]; then
            sudo -u "$CURRENT_USER" open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>/dev/null
        fi
    fi
else
    echo "[ERROR] Download may have failed - exit code: $EXIT_CODE" >> "$LOG"

    if [ -n "$CURRENT_USER" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ]; then
        sudo -u "$CURRENT_USER" osascript -e 'display notification "macOS update download encountered an issue. Check with IT." with title "macOS Update"' 2>/dev/null
    fi
fi

# Clean up - remove the LaunchDaemon after completion
launchctl unload /Library/LaunchDaemons/com.force-macos-update.download.plist 2>/dev/null
rm -f /Library/LaunchDaemons/com.force-macos-update.download.plist 2>/dev/null
rm -f /usr/local/bin/force-macos-update-download.sh 2>/dev/null

echo "[INFO] Cleanup complete" >> "$LOG"
DOWNLOADSCRIPT

chmod +x "$DOWNLOAD_SCRIPT"
log "[OK] Download script created at $DOWNLOAD_SCRIPT"

# --- CREATE AND LOAD LAUNCHDAEMON ---
log "[INFO] Creating LaunchDaemon for persistent download..."

cat > "$LAUNCHDAEMON_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.force-macos-update.download</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$DOWNLOAD_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/force-macos-update-download.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/force-macos-update-download.log</string>
</dict>
</plist>
EOF

chmod 644 "$LAUNCHDAEMON_PLIST"
chown root:wheel "$LAUNCHDAEMON_PLIST"
log "[OK] LaunchDaemon created at $LAUNCHDAEMON_PLIST"

# Load and start the LaunchDaemon
log "[INFO] Loading LaunchDaemon to start download..."
launchctl load "$LAUNCHDAEMON_PLIST" 2>&1 | tee -a "$LOG"

# Verify it started
sleep 2
if launchctl list | grep -q "com.force-macos-update.download"; then
    log "[OK] LaunchDaemon loaded successfully - download starting"
else
    log "[WARN] LaunchDaemon may not have loaded - attempting direct start..."
    launchctl start com.force-macos-update.download 2>&1 | tee -a "$LOG"
fi

# --- FINAL STATUS ---
log ""
log "=== Script Complete: $(date) ==="
log "[INFO] Download running via LaunchDaemon"
log "[INFO] Monitor progress: tail -f $DOWNLOAD_LOG"
log ""
log "=== Summary ==="
log "macOS Version: $CURRENT_VERSION"
log "Current User: $CURRENT_USER"
log "Main Log: $LOG"
log "Download Log: $DOWNLOAD_LOG"

exit 0
