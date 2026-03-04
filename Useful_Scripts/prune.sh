#!/bin/bash

# Configuration
NODE_IP="192.168.86.26"


DAYS_OLD=30
DEADLINE=$(date -d "$DAYS_OLD days ago" +%s)

# 1. Get the list (skipping the header)
# 2. Assign variables based on your columns
#    Note: 'read' handles the spaces between the columns automatically.
talosctl image ls --nodes $NODE_IP | tail -n +2 | while read -r node image digest size size2 created; do
    
    # Convert the ISO timestamp (2024-12-20T...) to Unix Epoch
    IMAGE_EPOCH=$(date -d "$created" +%s 2>/dev/null)
    # Skip if the date parsing fails
    if [ $? -ne 0 ]; then echo "FAILED" continue; fi

    if [ "$IMAGE_EPOCH" -lt "$DEADLINE" ]; then
        echo "Found old image: $image"
        echo "Created: $created | Digest: $digest"
        
        # Perform the removal
        # This will fail safely if the image is currently in use by a container.
        talosctl image rm --nodes $NODE_IP $digest
        echo "-----------------------------------"
    fi
done
