#!/bin/bash
# Force macOS to Check and Download Latest Updates
# Supports major version upgrades (e.g., Sequoia → Tahoe)
# For deployment via Rippling MDM
# Uses LaunchDaemon for persistent background download

LOG="/var/log/force-macos-update.log"
DOWNLOAD_LOG="/var/log/force-macos-update-download.log"
DOWNLOAD_SCRIPT="/usr/local/bin/force-macos-update-download.sh"
PROGRESS_SCRIPT="/usr/local/bin/force-macos-update-progress.sh"
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

# --- CREATE PROGRESS VIEWER SCRIPT ---
log "[INFO] Creating progress viewer script..."
mkdir -p /usr/local/bin

cat > "$PROGRESS_SCRIPT" << 'PROGRESSSCRIPT'
#!/bin/bash
clear
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    macOS UPDATE DOWNLOAD                         ║"
echo "║                                                                  ║"
echo "║  Your IT department is downloading a macOS upgrade.              ║"
echo "║  This may take 30-60 minutes. Please do not shut down.           ║"
echo "║                                                                  ║"
echo "║  Progress will appear below:                                     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "Waiting for download to start..."
echo ""

# Wait for log file to exist
while [ ! -f /var/log/force-macos-update-download.log ]; do
    sleep 1
done

# Show live progress
tail -f /var/log/force-macos-update-download.log
PROGRESSSCRIPT

chmod +x "$PROGRESS_SCRIPT"
log "[OK] Progress viewer script created"

# --- CREATE LAUNCHAGENT TO OPEN TERMINAL (runs in user context with GUI access) ---
log "[INFO] Creating LaunchAgent to show download progress..."

LAUNCHAGENT_PLIST="/Library/LaunchAgents/com.force-macos-update.progress.plist"

cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.force-macos-update.progress</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>Terminal</string>
        <string>/usr/local/bin/force-macos-update-progress.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
</dict>
</plist>
EOF

chmod 644 "$LAUNCHAGENT_PLIST"
chown root:wheel "$LAUNCHAGENT_PLIST"
log "[OK] LaunchAgent plist created"

# Load LaunchAgent for the current user
if [ -n "$CURRENT_USER_UID" ] && [ "$CURRENT_USER" != "root" ] && [ "$CURRENT_USER" != "loginwindow" ]; then
    # Load into user's GUI session
    launchctl asuser "$CURRENT_USER_UID" launchctl load "$LAUNCHAGENT_PLIST" 2>&1 | tee -a "$LOG"
    log "[OK] LaunchAgent loaded for user - Terminal window should open"
fi

# --- CREATE DOWNLOAD SCRIPT ---
log "[INFO] Creating persistent download script..."

cat > "$DOWNLOAD_SCRIPT" << 'DOWNLOADSCRIPT'
#!/bin/bash
LOG="/var/log/force-macos-update-download.log"

# Prevent Mac from sleeping during download
caffeinate -d -i -m -s &
CAFFEINATE_PID=$!
trap "kill $CAFFEINATE_PID 2>/dev/null" EXIT

echo "=== macOS Update Download Started: $(date) ===" > "$LOG"
echo "[INFO] Caffeinate enabled - Mac will not sleep during download" >> "$LOG"
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

echo "" >> "$LOG"
echo "========================================" >> "$LOG"
echo "  DOWNLOADING macOS INSTALLER" >> "$LOG"
echo "  Please wait... this takes 30-60 min" >> "$LOG"
echo "========================================" >> "$LOG"
echo "" >> "$LOG"

# Check for incremental updates first
echo "[INFO] Checking for updates..." >> "$LOG"
AVAILABLE=$(softwareupdate -l 2>&1)
echo "$AVAILABLE" >> "$LOG"

if echo "$AVAILABLE" | grep -q "No new software available"; then
    echo "" >> "$LOG"
    echo "[INFO] Listing available macOS installers..." >> "$LOG"

    # List available full installers and find the latest version
    INSTALLER_LIST=$(softwareupdate --list-full-installers 2>&1)
    echo "$INSTALLER_LIST" >> "$LOG"

    # Get the highest version number (latest macOS)
    LATEST_VERSION=$(echo "$INSTALLER_LIST" | grep -o 'Version: [0-9.]*' | head -1 | awk '{print $2}')

    if [ -n "$LATEST_VERSION" ]; then
        echo "" >> "$LOG"
        echo "[INFO] Latest available version: $LATEST_VERSION" >> "$LOG"
        echo "[INFO] Downloading macOS $LATEST_VERSION installer..." >> "$LOG"
        echo "" >> "$LOG"

        # Download the specific latest version
        softwareupdate --fetch-full-installer --full-installer-version "$LATEST_VERSION" 2>&1 | tee -a "$LOG"
        EXIT_CODE=${PIPESTATUS[0]}
    else
        echo "" >> "$LOG"
        echo "[WARN] Could not determine latest version, trying default..." >> "$LOG"
        softwareupdate --fetch-full-installer 2>&1 | tee -a "$LOG"
        EXIT_CODE=${PIPESTATUS[0]}
    fi

    echo "" >> "$LOG"
    echo "[INFO] Download exit code: $EXIT_CODE" >> "$LOG"
else
    echo "" >> "$LOG"
    echo "[INFO] Downloading incremental updates..." >> "$LOG"
    echo "" >> "$LOG"
    softwareupdate --download --all --force 2>&1 | tee -a "$LOG"
    EXIT_CODE=${PIPESTATUS[0]}
    echo "" >> "$LOG"
    echo "[INFO] Download exit code: $EXIT_CODE" >> "$LOG"
fi

echo "" >> "$LOG"
echo "========================================" >> "$LOG"
echo "=== Download Finished: $(date) ===" >> "$LOG"
echo "========================================" >> "$LOG"

# Re-get user in case they logged out/in during download
CURRENT_USER=$(stat -f "%Su" /dev/console)
CURRENT_USER_UID=$(id -u "$CURRENT_USER" 2>/dev/null)

# Check results and notify user
INSTALLER=$(ls -dt /Applications/Install\ macOS*.app 2>/dev/null | head -1)

if [ -n "$INSTALLER" ]; then
    INSTALLER_NAME=$(basename "$INSTALLER" .app)
    echo "" >> "$LOG"
    echo "╔══════════════════════════════════════════════════════════════════╗" >> "$LOG"
    echo "║  SUCCESS! macOS installer downloaded!                            ║" >> "$LOG"
    echo "║                                                                  ║" >> "$LOG"
    echo "║  Location: /Applications/$INSTALLER_NAME.app" >> "$LOG"
    echo "║                                                                  ║" >> "$LOG"
    echo "║  To install: Open Finder > Applications > $INSTALLER_NAME" >> "$LOG"
    echo "╚══════════════════════════════════════════════════════════════════╝" >> "$LOG"
    echo "" >> "$LOG"

    # Try to show dialog
    run_as_user osascript -e "display dialog \"macOS upgrade is ready!

The installer is in your Applications folder:
$INSTALLER_NAME

To install:
1. Open Finder → Applications
2. Double-click '$INSTALLER_NAME'
3. Follow the prompts

Your Mac will restart during upgrade.\" with title \"macOS Update Ready\" buttons {\"Open Applications\", \"OK\"} default button \"Open Applications\"" 2>/dev/null

    if [ $? -eq 0 ]; then
        run_as_user open /Applications 2>/dev/null
    fi

elif [ $EXIT_CODE -eq 0 ]; then
    echo "" >> "$LOG"
    echo "[OK] Updates downloaded! Go to System Settings > Software Update to install." >> "$LOG"

    run_as_user osascript -e 'display dialog "macOS updates are ready!

Go to System Settings > General > Software Update to install." with title "macOS Update Ready" buttons {"Open Settings", "OK"} default button "Open Settings"' 2>/dev/null

    if [ $? -eq 0 ]; then
        run_as_user open "x-apple.systempreferences:com.apple.Software-Update-Settings.extension" 2>/dev/null
    fi
else
    echo "" >> "$LOG"
    echo "[ERROR] Download may have failed. Please contact IT support." >> "$LOG"

    run_as_user osascript -e 'display dialog "macOS update download encountered an issue.

Please contact IT support." with title "macOS Update Error" buttons {"OK"} default button "OK"' 2>/dev/null
fi

# Clean up LaunchDaemon and LaunchAgent
echo "" >> "$LOG"
echo "[INFO] Cleaning up..." >> "$LOG"
launchctl unload /Library/LaunchDaemons/com.force-macos-update.download.plist 2>/dev/null
launchctl unload /Library/LaunchAgents/com.force-macos-update.progress.plist 2>/dev/null
rm -f /Library/LaunchDaemons/com.force-macos-update.download.plist 2>/dev/null
rm -f /Library/LaunchAgents/com.force-macos-update.progress.plist 2>/dev/null
rm -f /usr/local/bin/force-macos-update-download.sh 2>/dev/null
rm -f /usr/local/bin/force-macos-update-progress.sh 2>/dev/null
echo "[OK] Done! You can close this window." >> "$LOG"
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
log ""
log "[INFO] A Terminal window should be open showing download progress"
log "[INFO] Download is running in background via LaunchDaemon"

exit 0
