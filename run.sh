#!/bin/bash

if [ -z "$REPO" ]; then
    echo "Error: REPO variable is not set. Exiting."
    exit 1
fi

if ! git -C /home/rancid/rancid/var rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Not a git repo. Initializing..."
    rm /home/rancid/rancid/var/.gitkeep
    git clone $REPO /home/rancid/rancid/var
fi

/home/rancid/rancid/bin/rancid-run

echo "$(date): Running 'cleanup logs'"
find /home/rancid/rancid/var/logs/* -mtime +0 -exec rm -f {} \;
