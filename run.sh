#!/bin/bash
echo "Starting..."

if [ -z "$REPO" ]; then
    echo ""
    echo "[$(date)]: Error: 'REPO' variable is not set! Exiting..."
    echo ""
    exit 1
fi

DIR="/home/rancid/rancid/var"

if ! git -C "$DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo ""
    echo "[$(date)]: Not a git repo! Initializing..."
    echo ""

    if [ -n "$(ls -A "$DIR")" ]; then
        echo ""
        echo "[$(date)]: Directory is not empty! Deleting contents..."
        rm -rf "$DIR"/* 2>/dev/null
        rm "$DIR"/.* 2>/dev/null
        echo ""
    fi
    echo ""
    git clone $REPO "$DIR"
    echo ""
else
    echo ""
    echo "[$(date)]: Repo already initialized! Skiping..."
    echo ""
fi

groupToRun=$1

groupName="$(echo $(hostname) | awk -F'.' '{print $2}' | awk -F'-' '{print $(NF-1)}' 2>/dev/null)"
if [ -n "$groupName" ]; then
    groupToRun="${!groupName}"
fi

echo ""
echo "[$(date)]: Running 'runcid'..."
echo ""
/home/rancid/rancid/bin/rancid-run $groupToRun
echo ""

if [ -n "$groupToRun" ]; then
    echo ""
    echo "[$(date)]: Running 'cleanup logs'..."
    find "$DIR"/logs/* -mtime +0 -exec rm -f {} \;
    echo ""
fi

echo "End."
