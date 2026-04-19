#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <legacy_qm_guest_exec|ssh> [args...]" >&2
    exit 64
fi

mode="$1"
shift

case "$mode" in
    legacy|legacy_qm_guest_exec)
        if [ "$#" -ne 4 ]; then
            echo "Usage: $0 legacy_qm_guest_exec <vmid> <guest_shell> <remote_script> <disk_device>" >&2
            exit 64
        fi

        vmid="$1"
        guest_shell="$2"
        remote_script="$3"
        disk_device="$4"

        temprtv="$(qm guest exec "$vmid" -- "$guest_shell" -c "$remote_script $disk_device" | grep data | awk '{print $3}' | sed -E 's/"//g;s/(\\n)+//g')"
        printf '%s\n' "$temprtv"
        ;;
    ssh)
        if [ "$#" -ne 5 ]; then
            echo "Usage: $0 ssh <host> <user> <port> <remote_script> <connect_timeout>" >&2
            exit 64
        fi

        host="$1"
        user="$2"
        port="$3"
        remote_script="$4"
        connect_timeout="$5"

        ssh \
            -o BatchMode=yes \
            -o ConnectTimeout="$connect_timeout" \
            -p "$port" \
            "${user}@${host}" \
            "$remote_script"
        ;;
    *)
        echo "Unknown mode: $mode" >&2
        exit 64
        ;;
esac
