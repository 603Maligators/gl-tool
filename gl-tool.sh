#!/bin/bash
cd /home/graniteledger/graniteledger
LOG="/home/graniteledger/deploy.log"
COMMAND=$1
ARG=$2

function sync_code() {
    echo "[$(date)] --- Starting Sync ---" | tee -a $LOG

    if ! git diff-index --quiet HEAD; then
        echo "[$(date)] Local changes detected, pushing to GitHub..." | tee -a $LOG
        git add .
        git commit -m "Auto-commit from Pi on $(date)"
        git push origin main
        echo "[$(date)] Push complete." | tee -a $LOG
    else
        echo "[$(date)] No local changes to push." | tee -a $LOG
    fi

    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git ls-remote origin main | cut -f1)

    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "[$(date)] New commits detected, pulling & restarting..." | tee -a $LOG
        git pull origin main
        sudo systemctl restart graniteledger
        echo "[$(date)] Done." | tee -a $LOG
    else
        echo "[$(date)] No new commits found." | tee -a $LOG
    fi

    echo "[$(date)] --- Sync Finished ---" | tee -a $LOG
    tail -n 10 $LOG
}

function version_lock() {
    CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
    if [ -z "$CURRENT_TAG" ]; then CURRENT_TAG="v0.0"; fi
    NEW_TAG="v$(echo $CURRENT_TAG | awk -F. '{printf "%d.%d\n", $1, $2 + 1}')"

    echo "[$(date)] Locking new version: $NEW_TAG" | tee -a $LOG
    git add .
    git commit -m "Version $NEW_TAG checkpoint" || echo "No changes to commit."
    git push origin main
    git tag -a $NEW_TAG -m "GraniteLedger $NEW_TAG"
    git push origin $NEW_TAG

    echo "[$(date)] Version $NEW_TAG locked." | tee -a $LOG
    echo "Recent versions:" | tee -a $LOG
    git tag --sort=-creatordate | head -n 5 | tee -a $LOG
}

function rollback_version() {
    if [ -z "$ARG" ]; then
        echo "Usage: gl-tool rollback <version_tag>"
        echo "Recent tags:"
        git tag --sort=-creatordate | head -n 5
        exit 1
    fi

    if ! git rev-parse "$ARG" >/dev/null 2>&1; then
        echo "Tag '$ARG' not found!"
        git tag --sort=-creatordate | head -n 10
        exit 1
    fi

    echo "[$(date)] Rolling back to $ARG..." | tee -a $LOG
    git fetch --all
    git checkout "$ARG"
    sudo systemctl restart graniteledger
    echo "[$(date)] Rollback to $ARG complete." | tee -a $LOG
}

function current_status() {
    CURRENT_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "No version tag found")

    echo "=============================="
    echo "GraniteLedger Status Snapshot"
    echo "=============================="
    echo "Current Version: $CURRENT_TAG"
    echo
    echo "Last 5 Versions:"
    git tag --sort=-creatordate | head -n 5
    echo
    echo "Service Status (graniteledger):"
    if systemctl is-active --quiet graniteledger; then
        echo "✅ Running"
    else
        echo "❌ Not Running"
    fi
    echo
    echo "Last 5 Log Entries:"
    tail -n 5 $LOG
    echo "=============================="
}

function show_help() {
    echo "GraniteLedger Command Line Tool (gl-tool)"
    echo "-----------------------------------------"
    echo "Usage: gl-tool <command> [args]"
    echo
    echo "Commands:"
    echo "  sync          Push/pull changes and restart GraniteLedger"
    echo "  version       Lock in a new version tag and push it"
    echo "  rollback      Revert GraniteLedger to an earlier tag"
    echo "  current       Show current status, logs, service info"
    echo "  install       Set up alias and permissions for gl-tool"
    echo "  upgrade       Replace gl-tool with latest GitHub version"
    echo "  rollback-tool Revert gl-tool CLI to an earlier version tag"
    echo "  help          Show this help message"
    echo
}

function install_tool() {
    echo "Installing gl-tool..."
    chmod +x /home/graniteledger/gl-tool.sh

    if ! grep -q "alias gl-tool=" ~/.bashrc; then
        echo "alias gl-tool='/home/graniteledger/gl-tool/gl-tool.sh'" >> ~/.bashrc
        echo "Alias added to ~/.bashrc"
    else
        echo "Alias already exists."
    fi

    source ~/.bashrc
    echo "✅ Installation complete! Try: gl-tool help"
}

function upgrade_tool() {
    echo "Checking for updates..."

    RAW_URL="https://raw.githubusercontent.com/603Maligators/gl-tool/main/gl-tool.sh"  # <--- Replace this

    cp /home/graniteledger/gl-tool.sh /home/graniteledger/gl-tool.sh.bak

    curl -fsSL $RAW_URL -o /home/graniteledger/gl-tool.sh

    if [ $? -eq 0 ]; then
        chmod +x /home/graniteledger/gl-tool.sh
        echo "✅ gl-tool updated successfully!"
        echo "Previous version saved as gl-tool.sh.bak"
    else
        echo "❌ Failed to update. Restoring backup..."
        mv /home/graniteledger/gl-tool.sh.bak /home/graniteledger/gl-tool.sh
    fi
}

function rollback_tool() {
    if [ -z "$ARG" ]; then
        echo "Usage: gl-tool rollback-tool <version_tag>"
        echo "Available tool versions:"
        git -C /home/graniteledger/gl-tool tag --sort=-creatordate | head -n 5
        exit 1
    fi

    echo "Rolling back gl-tool to version $ARG..."

    cd /home/graniteledger/gl-tool

    if ! git rev-parse "$ARG" >/dev/null 2>&1; then
        echo "❌ Tag '$ARG' not found!"
        exit 1
    fi

    git checkout "$ARG"
    cp gl-tool.sh /home/graniteledger/gl-tool.sh
    chmod +x /home/graniteledger/gl-tool.sh

    echo "✅ gl-tool rolled back to $ARG"
    echo "Note: You are now in a detached HEAD state inside /gl-tool"
}

# Main switch
case "$COMMAND" in
    sync) sync_code ;;
    version) version_lock ;;
    rollback) rollback_version ;;
    current) current_status ;;
    install) install_tool ;;
    upgrade) upgrade_tool ;;
    rollback-tool) rollback_tool ;;
    help) show_help ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Use: gl-tool help"
        ;;
esac
