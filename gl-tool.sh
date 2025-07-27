#!/bin/bash
cd /home/graniteledger/graniteledger
LOG="/home/graniteledger/deploy.log"

COMMAND=$1
ARG=$2

function sync_code() {
    echo "[$(date)] --- Starting Sync ---" | tee -a $LOG

    # Push local changes
    if ! git diff-index --quiet HEAD; then
        echo "[$(date)] Local changes detected, pushing to GitHub..." | tee -a $LOG
        git add .
        git commit -m "Auto-commit from Pi on $(date)"
        git push origin main
        echo "[$(date)] Push complete." | tee -a $LOG
    else
        echo "[$(date)] No local changes to push." | tee -a $LOG
    fi

    # Pull remote changes
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
    echo "  sync        Push local changes, pull updates, and restart service."
    echo "  version     Create a new version tag (auto-increment) and push to GitHub."
    echo "  rollback    Roll back to a specific version tag (e.g., gl-tool rollback v0.1)."
    echo "  current     Show current version, recent tags, service status, and logs."
    echo "  install     Install gl-tool (set alias, permissions)."
    echo "  help        Show this help message."
    echo
}

function install_tool() {
    echo "Installing gl-tool..."
    chmod +x /home/graniteledger/gl-tool.sh

    if ! grep -q "alias gl-tool=" ~/.bashrc; then
        echo "alias gl-tool='/home/graniteledger/gl-tool.sh'" >> ~/.bashrc
        echo "Alias added to ~/.bashrc"
    else
        echo "Alias already exists."
    fi

    source ~/.bashrc
    echo "Installation complete! Try: gl-tool help"
}

# Main command switch
case "$COMMAND" in
    sync) sync_code ;;
    version) version_lock ;;
    rollback) rollback_version ;;
    current) current_status ;;
    help) show_help ;;
    install) install_tool ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Use: gl-tool help"
        ;;
esac
