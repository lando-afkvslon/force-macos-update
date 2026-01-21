#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM
# Uses LaunchDaemon for persistent background download

LOG="/var/log/force-macos-update.log"
DOWNLOAD_LOG="/var/log/force-macos-update-download.log"
DOWNLOAD_SCRIPT="/usr/local/bin/force-macos-update-download.sh"
LAUNCHDAEMON_PLIST="/Library/LaunchDaemons/com.force-macos-update.download.plist"

# Function to log to both stdout (for Rippling) and log file
log() {
    echo "$1"
    echo "$1" >> "$LOG"
}

log "=== Force macOS Update Started: $(date) ==="

# --- VERIFY ROOT PERMISSIONS ---
if [ "$(id -u)" -ne 0 ]; then
    log "[ERROR] This script must be run as root!"
    log "[ERROR] Current user: $(whoami) (UID: $(id -u))"
    exit 1
fi
log "[OK] Running as root (UID: $(id -u))"

# Get current logged-in user and their UID
CURRENT_USER=$(stat -f "%Su" /dev/console)
CURRENT_USER_UID=$(id -u "$CURRENT_USER" 2>/dev/null)
log "[INFO] Console user: $CURRENT_USER (UID: $CURRENT_USER_UID)"

# Get current macOS version
CURRENT_VERSION=$(sw_vers -productVersion)
log "[INFO] Current macOS version: $CURRENT_VERSION"

# Function to run command as the logged-in user (for GUI operations)
run_as_user() {
    if [ -n "$CURRENT_USER_UID" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ] && [ "$CURRENT_USER" != "_mbsetupuser" ]; then
        launchctl asuser "$CURRENT_USER_UID" sudo -u "$CURRENT_USER" "$@"
    fi
}

# --- TEST GUI ACCESS ---
log "[INFO] Testing GUI access for user notifications..."
run_as_user osascript -e 'display notification "macOS Update script starting..." with title "IT Update"' 2>&1 | tee -a "$LOG"
log "[OK] GUI notification test sent"

# --- REMOVE UPDATE BLOCKERS AND RESTRICTIONS ---
log "[INFO] Checking for update blockers and restrictions..."

# List current profiles
log "[INFO] Current configuration profiles:"
profiles list 2>&1 | tee -a "$LOG"

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

# --- OPEN SYSTEM SETTINGS NOW (before background process) ---
log "[INFO] Opening System Settings > Software Update..."
run_as_user open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>&1 | tee -a "$LOG"
log "[OK] System Settings open command sent"

# --- CREATE DOWNLOAD SCRIPT ---
log "[INFO] Creating persistent download script..."

mkdir -p /usr/local/bin

cat > "$DOWNLOAD_SCRIPT" << 'DOWNLOADSCRIPT'
#!/bin/bash
LOG="/var/log/force-macos-update-download.log"

echo "=== macOS Update Download Started: $(date) ===" > "$LOG"
echo "[INFO] Running as: $(whoami) (UID: $(id -u))" >> "$LOG"

# Get current console user and UID
CURRENT_USER=$(stat -f "%Su" /dev/console)
CURRENT_USER_UID=$(id -u "$CURRENT_USER" 2>/dev/null)
echo "[INFO] Console user: $CURRENT_USER (UID: $CURRENT_USER_UID)" >> "$LOG"

# Function to run as user for GUI
run_as_user() {
    if [ -n "$CURRENT_USER_UID" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ] && [ "$CURRENT_USER" != "_mbsetupuser" ]; then
        launchctl asuser "$CURRENT_USER_UID" sudo -u "$CURRENT_USER" "$@"
    fi
}

# Notify user download is starting
echo "[INFO] Sending start notification to user..." >> "$LOG"
run_as_user osascript -e 'display notification "Downloading macOS upgrade. This may take 30-60 minutes. Do not shut down your Mac." with title "macOS Update"' 2>&1 >> "$LOG"

# Open System Settings
echo "[INFO] Opening System Settings..." >> "$LOG"
run_as_user open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>&1 >> "$LOG"

# Small delay to let notification show
sleep 2

# Check for incremental updates first
echo "[INFO] Checking for updates..." >> "$LOG"
AVAILABLE=$(softwareupdate -l 2>&1)
echo "$AVAILABLE" >> "$LOG"

if echo "$AVAILABLE" | grep -q "No new software available"; then
    echo "" >> "$LOG"
    echo "[INFO] No incremental updates found" >> "$LOG"
    echo "[INFO] Downloading full macOS installer..." >> "$LOG"
    echo "[INFO] This will take 30-60 minutes..." >> "$LOG"
    echo "" >> "$LOG"

    # Download full installer
    softwareupdate --fetch-full-installer 2>&1 | tee -a "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}
    echo "" >> "$LOG"
    echo "[INFO] softwareupdate exit code: $EXIT_CODE" >> "$LOG"
else
    echo "" >> "$LOG"
    echo "[INFO] Incremental updates found - downloading..." >> "$LOG"
    echo "" >> "$LOG"
    softwareupdate --download --all --force 2>&1 | tee -a "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}
    echo "" >> "$LOG"
    echo "[INFO] softwareupdate exit code: $EXIT_CODE" >> "$LOG"
fi

echo "" >> "$LOG"
echo "=== Download Finished: $(date) ===" >> "$LOG"

# Re-get user in case they logged out/in during download
CURRENT_USER=$(stat -f "%Su" /dev/console)
CURRENT_USER_UID=$(id -u "$CURRENT_USER" 2>/dev/null)

# Check results and notify user
INSTALLER=$(ls -dt /Applications/Install\ macOS*.app 2>/dev/null | head -1)

if [ -n "$INSTALLER" ]; then
    INSTALLER_NAME=$(basename "$INSTALLER" .app)
    echo "[OK] SUCCESS - Found installer: $INSTALLER" >> "$LOG"

    # Show completion dialog
    echo "[INFO] Showing completion dialog..." >> "$LOG"
    run_as_user osascript -e "display dialog \"macOS upgrade is ready!

The installer has been downloaded to your Applications folder:
$INSTALLER_NAME

To install:
1. Open Finder → Applications
2. Double-click '$INSTALLER_NAME'
3. Follow the prompts

Your Mac will restart during the upgrade.\" with title \"macOS Update Ready\" buttons {\"Open Applications\", \"Later\"} default button \"Open Applications\"" 2>&1 >> "$LOG"

    DIALOG_RESULT=$?
    echo "[INFO] Dialog result: $DIALOG_RESULT" >> "$LOG"

    if [ $DIALOG_RESULT -eq 0 ]; then
        run_as_user open /Applications 2>&1 >> "$LOG"
    fi

elif [ $EXIT_CODE -eq 0 ]; then
    echo "[OK] Updates downloaded successfully" >> "$LOG"

    run_as_user osascript -e "display dialog \"macOS updates are ready to install.

Go to System Settings > General > Software Update to install.

Your Mac will restart during installation.\" with title \"macOS Update Ready\" buttons {\"Open Settings\", \"Later\"} default button \"Open Settings\"" 2>&1 >> "$LOG"

    if [ $? -eq 0 ]; then
        run_as_user open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>&1 >> "$LOG"
    fi
else
    echo "[ERROR] Download may have failed - exit code: $EXIT_CODE" >> "$LOG"
    run_as_user osascript -e 'display dialog "macOS update download encountered an issue. Please contact IT support." with title "macOS Update Error" buttons {"OK"} default button "OK"' 2>&1 >> "$LOG"
fi

# Clean up
echo "[INFO] Cleaning up..." >> "$LOG"
launchctl unload /Library/LaunchDaemons/com.force-macos-update.download.plist 2>/dev/null
rm -f /Library/LaunchDaemons/com.force-macos-update.download.plist 2>/dev/null
rm -f /usr/local/bin/force-macos-update-download.sh 2>/dev/null
echo "[OK] Cleanup complete" >> "$LOG"
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
        <string>/usr/local/bin/force-macos-update-download.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/force-macos-update-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/force-macos-update-daemon.log</string>
</dict>
</plist>
EOF

chmod 644 "$LAUNCHDAEMON_PLIST"
chown root:wheel "$LAUNCHDAEMON_PLIST"
log "[OK] LaunchDaemon plist created"

# Load the LaunchDaemon
log "[INFO] Loading LaunchDaemon..."
launchctl load "$LAUNCHDAEMON_PLIST" 2>&1 | tee -a "$LOG"
LOAD_RESULT=$?
log "[INFO] launchctl load exit code: $LOAD_RESULT"

sleep 2

# Verify it's running
if launchctl list | grep -q "com.force-macos-update.download"; then
    log "[OK] LaunchDaemon is running"
else
    log "[WARN] LaunchDaemon not in list - trying direct start..."
    launchctl start com.force-macos-update.download 2>&1 | tee -a "$LOG"
    sleep 1
    if launchctl list | grep -q "com.force-macos-update.download"; then
        log "[OK] LaunchDaemon started after retry"
    else
        log "[ERROR] LaunchDaemon failed to start - running download directly..."
        /bin/bash "$DOWNLOAD_SCRIPT" &
        log "[INFO] Started download script directly (PID: $!)"
    fi
fi

# --- FINAL STATUS ---
log ""
log "=== Script Complete: $(date) ==="
log ""
log "=== Summary ==="
log "macOS Version: $CURRENT_VERSION"
log "Console User: $CURRENT_USER (UID: $CURRENT_USER_UID)"
log "Main Log: $LOG"
log "Download Log: $DOWNLOAD_LOG"
log "Daemon Log: /var/log/force-macos-update-daemon.log"
log ""
log "[INFO] Download is running in background via LaunchDaemon"
log "[INFO] To monitor: tail -f /var/log/force-macos-update-download.log"

exit 0
