#!/bin/sh

TRUENAS_CORE_CONFIG_PROFILE="TrueNAS-CORE"
PROXMOX_CONFIG_PROFILE="Proxmox"
PFSENSE_CONFIG_PROFILE="pfSense"

uninstall_truenas_core() {
    echo "Stopping the script now."
    /root/fan-control/fan-control.sh stop

    echo "************************"
    echo "* USER ACTION REQUIRED *"
    echo "************************"
    echo "Go to the TrueNAS Core WebUI, log in, go to following menus:"
    echo "Tasks -> Init/Shutdown Scripts"
    echo "Remove the task you created to start script on boot."
}

uninstall_proxmox() {
    echo "Stopping fan-control service"
    systemctl stop fan-control.service
    sleep 2
    systemctl status fan-control.service

    echo "Disabling fan-control service"
    systemctl disable fan-control.service

    echo "Reloading daemons"
    systemctl daemon-reload

    echo "Removing service file"
    rm /etc/systemd/system/fan-control.service
}

uninstall_pfsense() {
    echo "Stopping the script now."
    /root/fan-control/fan-control.sh stop

    echo "Removing rc.d file"
    rm /usr/local/etc/rc.d/fan-control.sh
}

main() {
    # Require root permissions
    if [ "$(id -u)" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi

    # Prompt user for OS
    echo "What OS are you running on?"
    echo "1 = TrueNAS CORE"
    echo "2 = Proxmox"
    echo "3 = pfSense"
    read -p "My OS: " USER_OS
    case $USER_OS in
        1)
            CONFIG_PROFILE="$TRUENAS_CORE_CONFIG_PROFILE"
            ;;
        2)
            CONFIG_PROFILE="$PROXMOX_CONFIG_PROFILE"
            ;;
        3)
            CONFIG_PROFILE="$PFSENSE_CONFIG_PROFILE"
            ;;
        *) echo "You didn't enter a proper selection, try again please." ;;
    esac
    echo "You selected $CONFIG_PROFILE"
    echo "If you selected incorrectly, Ctrl+C now in next 5 seconds!"
    sleep 5

    # Run uninstall for selected OS
    case $CONFIG_PROFILE in
        "$TRUENAS_CORE_CONFIG_PROFILE")
            uninstall_truenas_core
            ;;
        "$PROXMOX_CONFIG_PROFILE")
            uninstall_proxmox
            ;;
        "$PFSENSE_CONFIG_PROFILE")
            uninstall_pfsense
            ;;
    esac

    echo "You are now stopped and it won't auto start on boot. If you'd like, run the following command to remove:"
    echo "rm -r /root/fan-control/"
}

main "$@"
