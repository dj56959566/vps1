#!/bin/bash
# highcpu_alert.sh
# Real-time thread CPU monitor with alert
# Author: YourName
# GitHub: https://github.com/yourname/highcpu-alert

# ------------- Configuration -------------
LOAD_THRESHOLD=2       # Load average threshold
CPU_THRESHOLD=80       # Single thread CPU% threshold
INTERVAL=1             # Refresh interval in seconds
TOP_COUNT=20           # Number of threads to show
# ----------------------------------------

while true; do
    clear
    DATE_NOW=$(date)
    echo "Thread CPU Monitor with Alert - $DATE_NOW"
    echo "TID     CPU%    COMMAND"
    echo "-----------------------"

    # Get current load
    LOAD=$(cat /proc/loadavg | awk '{print $1}')

    # Highlight if load exceeds threshold
    if (( $(echo "$LOAD > $LOAD_THRESHOLD" | bc -l) )); then
        echo -e "\033[1;33mHigh Load: $LOAD\033[0m"
        # Optional: beep sound
        echo -e "\a"
    fi

    # Show top threads by CPU
    ps -eLo tid,%cpu,comm --sort=-%cpu | tail -n +2 | head -n $TOP_COUNT | \
    awk -v cpu_thr=$CPU_THRESHOLD '{
        if($2+0 > cpu_thr)
            printf "\033[1;31m%s %s %s\033[0m\n", $1,$2,$3; 
        else
            printf "%s %s %s\n", $1,$2,$3;
    }'

    sleep $INTERVAL
done
