#!/bin/sh

set -eu

INSTALL_DIR="/root/fan-control"
SERVICE_LINK="/etc/systemd/system/fan-control.service"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULTS_DIR="$SCRIPT_DIR/defaults"

TRUENAS_SHEBANG="#!/usr/local/bin/python3"
PROXMOX_SHEBANG="#!/usr/bin/python3"
PFSENSE_SHEBANG="#!/usr/local/bin/python3.11"

TRUENAS_CORE_CONFIG_PROFILE="TrueNAS-CORE"
PROXMOX_CONFIG_PROFILE="Proxmox"
PFSENSE_CONFIG_PROFILE="pfSense"

abort() {
    echo "$1" >&2
    exit "${2:-1}"
}

pause_for_abort() {
    echo "$1"
    sleep 5
}

ensure_required_files() {
    for file in \
        "$DEFAULTS_DIR/fan-control.py" \
        "$DEFAULTS_DIR/gen-config.py" \
        "$DEFAULTS_DIR/fan-control.sh" \
        "$DEFAULTS_DIR/fan-control.service"
    do
        if [ ! -f "$file" ]; then
            abort "Missing required file: $file"
        fi
    done
}

file_mode() {
    if [ "$OS_FAMILY" = "linux" ]; then
        stat -c "%a" "$1"
    else
        stat -f "%Lp" "$1"
    fi
}

check_script_exec() {
    for file in "$@"
    do
        mode=$(file_mode "$file")
        if [ "$mode" = "755" ] || [ "$mode" = "0755" ]; then
            echo "$(basename "$file") has proper permissions"
        else
            echo "$(basename "$file") did not get proper permissions, please manually run the following!"
            echo "chmod 755 $file"
        fi
    done
}

install_python_script() {
    shebang="$1"
    source_path="$2"
    target_path="$3"

    echo "creating $(basename "$target_path")"
    printf '%s\n' "$shebang" > "$target_path"
    tail -n +2 "$source_path" >> "$target_path"
}

copy_runtime_files() {
    install_python_script "$SHEBANG" "$DEFAULTS_DIR/fan-control.py" "$INSTALL_DIR/fan-control.py"
    install_python_script "$SHEBANG" "$DEFAULTS_DIR/gen-config.py" "$INSTALL_DIR/gen-config.py"

    if [ "$CONFIG_PROFILE" = "$PROXMOX_CONFIG_PROFILE" ]; then
        echo "copying service file to $INSTALL_DIR/"
        cp "$DEFAULTS_DIR/fan-control.service" "$INSTALL_DIR/fan-control.service"
    else
        echo "copying fan-control.sh to $INSTALL_DIR/"
        cp "$DEFAULTS_DIR/fan-control.sh" "$INSTALL_DIR/fan-control.sh"
    fi

    echo "making appropriate files executable"
    chmod 755 "$INSTALL_DIR/gen-config.py" "$INSTALL_DIR/fan-control.py"
    if [ "$CONFIG_PROFILE" != "$PROXMOX_CONFIG_PROFILE" ]; then
        chmod 755 "$INSTALL_DIR/fan-control.sh"
        check_script_exec "$INSTALL_DIR/gen-config.py" "$INSTALL_DIR/fan-control.py" "$INSTALL_DIR/fan-control.sh"
    else
        check_script_exec "$INSTALL_DIR/gen-config.py" "$INSTALL_DIR/fan-control.py"
    fi
}

setup_truenas_core() {
    echo "************************"
    echo "* USER ACTION REQUIRED *"
    echo "************************"
    echo "Go to the TrueNAS Core WebUI, log in, and follow these menus:"
    echo "Tasks -> Init/Shutdown Scripts"
    echo "Add a task (top right)"
    echo "Description: fan-control"
    echo "Type: Command"
    echo "Command: $INSTALL_DIR/fan-control.sh start"
    echo "When: Post Init"
    echo "Enable the task and save it."
    echo "fan-control.py is set up. Starting the script now."

    nohup "$INSTALL_DIR/fan-control.sh" start >/dev/null 2>&1 &
}

setup_proxmox() {
    command -v systemctl >/dev/null 2>&1 || abort "systemctl not found"

    echo "Creating link to service file"
    rm -f "$SERVICE_LINK"
    ln -s "$INSTALL_DIR/fan-control.service" "$SERVICE_LINK"

    echo "reloading daemons"
    systemctl daemon-reload

    echo "enabling fan-control.service"
    systemctl enable fan-control.service

    echo "starting fan-control"
    systemctl restart fan-control.service

    sleep 2

    if ! systemctl --no-pager --full status fan-control.service; then
        echo "fan-control.service did not report a healthy status"
    fi
}

setup_pfsense() {
    echo "Copying fan-control.sh to /usr/local/etc/rc.d/ so it can auto start on reboots"
    cp "$INSTALL_DIR/fan-control.sh" /usr/local/etc/rc.d/fan-control.sh
    chmod 755 /usr/local/etc/rc.d/fan-control.sh

    echo "fan-control.py is set up. Starting the script."
    pause_for_abort "Ctrl+C in next 5 seconds to quit without starting the script."
    nohup "$INSTALL_DIR/fan-control.sh" start >/dev/null 2>&1 &
}

main() {
    # Require root permissions
    if [ "$(id -u)" -ne 0 ]; then
        abort "Please run as root"
    fi

    # Ensure required files are present before starting
    ensure_required_files

    # Prompt user for OS
    echo "What OS are you installing on?"
    echo "1 = TrueNAS CORE"
    echo "2 = Proxmox"
    echo "3 = pfSense"
    read -p "My OS: " USER_OS
    case "$USER_OS" in
        1)
            CONFIG_PROFILE="$TRUENAS_CORE_CONFIG_PROFILE"
            SHEBANG="$TRUENAS_SHEBANG"
            OS_FAMILY="bsd"
            ;;
        2)
            CONFIG_PROFILE="$PROXMOX_CONFIG_PROFILE"
            SHEBANG="$PROXMOX_SHEBANG"
            OS_FAMILY="linux"
            ;;
        3)
            CONFIG_PROFILE="$PFSENSE_CONFIG_PROFILE"
            SHEBANG="$PFSENSE_SHEBANG"
            OS_FAMILY="bsd"
            ;;
        *)
            abort "You didn't enter a proper selection, try again please." 2
            ;;
    esac
    echo "You selected $CONFIG_PROFILE"
    pause_for_abort "If you selected incorrectly, Ctrl+C now in next 5 seconds!"


    # Install prerequisites if needed
    if [ "$CONFIG_PROFILE" = "$PROXMOX_CONFIG_PROFILE" ]; then
        command -v apt-get >/dev/null 2>&1 || abort "apt-get not found"
        echo "Installing requirements via apt. Already installed packages will be skipped."
        apt-get install -y ipmitool lm-sensors
    fi

    # Ensure install directory exists
    mkdir -p "$INSTALL_DIR"

    # Copy runtime files and set permissions
    copy_runtime_files

    # Generate config.toml if it doesn't exist
    if [ ! -f "$INSTALL_DIR/config.toml" ]; then
        echo "config.toml not found in $INSTALL_DIR"
        pause_for_abort "If you don't want to generate a config file now, press Ctrl+C in next 5 seconds to quit"
        echo "Executing gen-config.py to generate the config file"
        (
            cd "$INSTALL_DIR"
            "$INSTALL_DIR/gen-config.py" --profile "$CONFIG_PROFILE"
        )
    fi

    # Perform final OS-specific setup
    case "$CONFIG_PROFILE" in
        "$TRUENAS_CORE_CONFIG_PROFILE")
            setup_truenas_core
            ;;
        "$PROXMOX_CONFIG_PROFILE")
            setup_proxmox
            ;;
        "$PFSENSE_CONFIG_PROFILE")
            setup_pfsense
            ;;
    esac
}

main "$@"
