#!/bin/bash
# 文件名：highcpu_threads.sh
# 实时显示线程 CPU 使用率，超过阈值高亮

THRESHOLD=10  # CPU 使用率阈值百分比
INTERVAL=1    # 刷新间隔，秒

while true; do
    clear
    echo "High CPU Threads Monitor (Threshold: $THRESHOLD%) - $(date)"
    echo "PID     TID     CPU%    MEM%    COMMAND"
    echo "-----------------------------------------"
    ps -eLo pid,tid,%cpu,%mem,comm --sort=-%cpu | tail -n +2 | head -n 20 | \
    awk -v threshold=$THRESHOLD '{
        if($3+0 > threshold)
            printf "\033[1;31m%s %s %s %s %s\033[0m\n", $1,$2,$3,$4,$5;
        else
            printf "%s %s %s %s %s\n", $1,$2,$3,$4,$5;
    }'
    sleep $INTERVAL
done
