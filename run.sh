#!/bin/bash

if [ -z "$REPO" ]; then
    echo "Error: REPO variable is not set. Exiting."
    exit 1
fi

DIR="/home/rancid/rancid/var"

if ! git -C "$DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Not a git repo. Initializing..."

    if [ -n "$(ls -A "$DIR")" ]; then
        echo "Directory is not empty. Deleting contents..."
        rm -rf "$DIR"/* 2>/dev/null
        rm "$DIR"/.* 2>/dev/null
    fi

    git clone $REPO "$DIR"
else
    echo "Repo already initialized. Skiping..."
fi

/home/rancid/rancid/bin/rancid-run

echo "$(date): Running 'cleanup logs'"
find "$DIR"/logs/* -mtime +0 -exec rm -f {} \;
