# Force macOS Update - Quick Reference

## Rippling Command (Copy & Paste)
```bash
cd /tmp && curl -fsSO https://raw.githubusercontent.com/lando-afkvslon/force-macos-update/main/force-macos-update.sh && /bin/bash force-macos-update.sh && rm force-macos-update.sh
```

## GitHub Repo
https://github.com/lando-afkvslon/force-macos-update

## Local Folder
`/Users/orlando/force-macos-update/`

---

## Check Logs on Target Mac
```bash
# Main log
cat /var/log/force-macos-update.log

# Download progress
cat /var/log/force-macos-update-download.log

# Watch live
tail -f /var/log/force-macos-update-download.log
```

---

## Update the Script

1. Edit: `/Users/orlando/force-macos-update/force-macos-update.sh`
2. Save changes
3. Push to GitHub:
```bash
cd /Users/orlando/force-macos-update
git add -A && git commit -m "Description of change" && git push
```

---

## Target Specific Version

Find this line in `force-macos-update.sh`:
```bash
LATEST_VERSION=$(echo "$INSTALLER_LIST" | grep "Deferred: NO" | grep -o 'Version: [0-9.]*' | head -1 | awk '{print $2}')
```

Replace with:
```bash
LATEST_VERSION="26.1"  # Change to desired version
```

---

## See Available Versions (run on any Mac)
```bash
softwareupdate --list-full-installers
```

---

## After Download

Installer location: `/Applications/Install macOS Tahoe.app`

User opens it → follows prompts → Mac restarts
