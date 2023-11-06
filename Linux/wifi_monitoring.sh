#!/bin/bash

# wifi_monitoring.sh - A Bash script to toggle a wireless interface between monitor and managed modes made by Apollyon
version="1.0"
# For the latest version visit: https://github.com/ApoIIy0n/Scripts

# This script checks the specified wireless interface's current mode and, based on the provided parameter,
# switches it to the requested mode while providing feedback to the user. It also checks for the existence
# and UP state of the interface and the availability of required commands (ip, iwconfig, sudo).

# Usage:
#   ./wifi_mode.sh [--version] <interface> <true|false>
#   - --version: Display the script's version.
#   - <interface>: Name of the wireless interface to configure (e.g., wlan0).
#   - <true|false>: Set to "true" to enable monitor mode, or "false" to enable managed mode.

# Changelog:
# - v1.0 (2023-11-06): Initial release

# Version check
if [ "$1" = "--version" ]; then
    echo "wifi_mode.sh version $version"
    exit 0
fi

# Check if the required parameters are provided
if [ "$#" -ne 3 ]; then
    echo "Error: Invalid usage. Please provide the required parameters."
    echo "Usage: ./wifi_mode.sh [--version] <interface> <true|false>"
    exit 1
fi


interface="$1"
mode="$2"

if ! type ip >/dev/null 2>&1 || ! type iwconfig >/dev/null 2>&1 || ! type sudo >/dev/null 2>&1; then
    echo "Error: Required commands (ip, iwconfig, sudo) not found. Please make sure they are installed."
    exit 1
fi

# Check if the specified interface exists and is in the UP state
if ! ip link show "$interface" 2>/dev/null | grep -q "state UP"; then
    echo "Error: The interface $interface does not exist or is not in the UP state."
    exit 1
fi

current_mode=$(sudo iwconfig "$interface" | grep "Mode" | awk -F"Mode:" '{print $2}' | awk '{print $1}')

if [ "$mode" = "true" ]; then
    if [ "$current_mode" = "Monitor" ]; then
        echo "$interface is already in monitor mode."
    else
        echo "Setting $interface down..."
        sudo ip link set "$interface" down

        echo "Setting $interface to monitor mode..."
        sudo iwconfig "$interface" mode monitor

        echo "Bringing $interface up..."
        sudo ip link set "$interface" up
        echo "$interface is now in monitor mode."
    fi
elif [ "$mode" = "false" ]; then
    if [ "$current_mode" = "Managed" ]; then
        echo "$interface is already in managed mode."
    else
        echo "Setting $interface down..."
        sudo ip link set "$interface" down

        echo "Setting $interface to managed mode..."
        sudo iwconfig "$interface" mode managed

        echo "Bringing $interface up..."
        sudo ip link set "$interface" up
        echo "$interface is now in managed mode."
    fi
else
    echo "Usage: $0 <interface> <true|false>"
    exit 1
fi
