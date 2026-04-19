#!/usr/bin/env bash
set -euo pipefail

printf "device,serial,model,by_id,temp_c\n"

escape_csv() {
    local value="${1:-}"
    value="${value//\"/\"\"}"
    printf '"%s"' "$value"
}

get_by_id() {
    local dev="$1"
    local id_path
    local resolved

    [ -d /dev/disk/by-id ] || return 0

    for id_path in /dev/disk/by-id/*; do
        [ -e "$id_path" ] || continue

        case "$(basename "$id_path")" in
            *-part[0-9]*)
                continue
                ;;
        esac

        resolved="$(readlink -f "$id_path" 2>/dev/null || true)"
        if [ "$resolved" = "$dev" ]; then
            basename "$id_path"
            return 0
        fi
    done
}

# Gets disk temperatures using smartctl for all disks found by lsblk, and outputs in CSV format.
# Output columns: device, serial number, model, temperature in Celsius (or "STANDBY" if the disk is in standby mode).

lsblk -dn -o NAME,TYPE | awk '$2 == "disk" {print $1}' | while read -r devname; do
    dev="/dev/${devname}"

    if ! out="$(smartctl -a -n standby "$dev" 2>/dev/null)"; then
        continue
    fi

    serial="$(awk -F: '/Serial Number:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' <<<"$out")"
    model="$(awk -F: '/Device Model:|Product:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' <<<"$out")"
    by_id="$(get_by_id "$dev")"

    if grep -qi "STANDBY" <<<"$out"; then
        temp="STANDBY"
    else
        temp="$(awk '$1 == 194 {print $10; exit}' <<<"$out")"
        [ -z "${temp:-}" ] && temp="$(awk -F: '/Current Drive Temperature:/ {gsub(/^[[:space:]]+| C$/, "", $2); print $2; exit}' <<<"$out")"
        [ -z "${temp:-}" ] && temp="$(awk -F: '/Temperature:/ {gsub(/^[[:space:]]+| Celsius$/, "", $2); print $2; exit}' <<<"$out")"
        [ -z "${temp:-}" ] && temp="NA"
    fi

    [ -z "${serial:-}" ] && serial="-"
    [ -z "${model:-}" ] && model="-"
    [ -z "${by_id:-}" ] && by_id="-"

    escape_csv "$devname"; printf ","
    escape_csv "$serial"; printf ","
    escape_csv "$model"; printf ","
    escape_csv "$by_id"; printf ","
    escape_csv "$temp"; printf "\n"
done
