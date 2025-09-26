#!/bin/bash

# ==============================================================================
# ipsec_manager v5.2 - Script to manage strongSwan connections
# Searches for the route configuration in:
# 1. $HOME/.config/ipsec_manager/routes.conf (user)
# 2. /etc/ipsec_manager/routes.conf (system)
# ==============================================================================

# --- SETTINGS ---
# Set DEBUG=true to see all commands the script executes.
# Set DEBUG=false for a clean output.
DEBUG=false

# --- EXTERNAL CONFIGURATION LOADING ---
declare -A VPN_ROUTES
USER_CONFIG="$HOME/.config/ipsec_manager/routes.conf"
SYSTEM_CONFIG="/etc/ipsec_manager/routes.conf"
CONFIG_FILE_LOADED=""

if [[ -f "$USER_CONFIG" ]]; then source "$USER_CONFIG"; CONFIG_FILE_LOADED="$USER_CONFIG";
elif [[ -f "$SYSTEM_CONFIG" ]]; then source "$SYSTEM_CONFIG"; CONFIG_FILE_LOADED="$SYSTEM_CONFIG";
fi

# --- FUNCTIONS ---
run_cmd() { if $DEBUG; then echo "DEBUG: Executing ->" "$@"; fi; "$@"; }

start_vpn() {
    if $DEBUG; then set -x; fi
    echo "INFO: Starting tunnel for '$VPN_NAME'..."
    run_cmd sudo systemctl restart strongswan.service
    if [ $? -ne 0 ]; then echo "ERROR: Could not restart the strongswan service."; set +x; exit 1; fi
    run_cmd sudo swanctl --load-all
    CHILD_NAME="${VPN_NAME}-tunnel"
    run_cmd sudo swanctl --initiate --child "$CHILD_NAME"
    if ! (run_cmd sudo swanctl --list-sas | grep "$CHILD_NAME" | grep -q -iE "ESTABLISHED|INSTALLED"); then
        echo "ERROR: Tunnel '$CHILD_NAME' was not established."; if $DEBUG; then set +x; fi; exit 1
    fi
    echo "INFO: Tunnel '$CHILD_NAME' established successfully."
    echo "INFO: Waiting 1 second for state to stabilize..."
    sleep 1
    echo "INFO: Detecting assigned virtual IP (VIP)..."
    VIRTUAL_IP=$(run_cmd sudo swanctl --list-sas | grep -A 5 "$CHILD_NAME" | grep -E '^\s*local\s' | awk '{print $2}' | sed 's/\/32//' | head -n 1)
    if [[ -z "$VIRTUAL_IP" ]]; then
        echo "ERROR: Could not detect the virtual IP."; echo "INFO: Terminating partial tunnel..."; run_cmd sudo swanctl --terminate --child "$CHILD_NAME"; if $DEBUG; then set +x; fi; exit 1
    fi
    echo "INFO: Virtual IP detected: $VIRTUAL_IP"
    echo "INFO: Adding network routes..."
    for route in ${VPN_ROUTES[$VPN_NAME]}; do
        echo "      -> Adding route: $route (source: $VIRTUAL_IP)"; run_cmd sudo ip route add "$route" dev "$NETWORK_DEVICE" src "$VIRTUAL_IP"
    done
    echo "=========================================="; echo "VPN '$VPN_NAME' ACTIVE (IP: $VIRTUAL_IP)"; echo "=========================================="
    if $DEBUG; then set +x; fi
}

stop_vpn() {
    if $DEBUG; then set -x; fi
    SAS_OUTPUT=$(run_cmd sudo swanctl --list-sas)
    # Final Fix: Specifically find the CHILD SA to get its name
    ACTIVE_CHILD_NAME=$(echo "$SAS_OUTPUT" | grep -- '-tunnel:' | grep -iE 'ESTABLISHED|INSTALLED' | awk '{print $1}' | sed 's/://' | head -n 1)
    
    if [[ -z "$ACTIVE_CHILD_NAME" ]]; then echo "INFO: No active VPN connection to stop."; if $DEBUG; then set +x; fi; exit 0; fi

    VPN_NAME=$(echo "$ACTIVE_CHILD_NAME" | sed 's/-tunnel//')
    echo "INFO: Active connection '$VPN_NAME' ($ACTIVE_CHILD_NAME) detected. Terminating..."

    echo "INFO: Removing network routes..."
    if [[ -n "${VPN_ROUTES[$VPN_NAME]}" ]]; then
        for route in ${VPN_ROUTES[$VPN_NAME]}; do
            if ip route show | grep -q "$route"; then echo "      -> Removing route: $route"; run_cmd sudo ip route del "$route"; fi
        done
    fi

    # Terminate the IKE_SA (the parent), which will automatically close the CHILD_SA and remove the virtual IP.
    run_cmd sudo swanctl --terminate --ike "$VPN_NAME"
    echo "=========================================="; echo "VPN '$VPN_NAME' DISCONNECTED"; echo "=========================================="
    if $DEBUG; then set +x; fi
}

status_vpn() {
    SAS_OUTPUT=$(sudo swanctl --list-sas)
    # Final Fix: Specifically find the CHILD SA to parse its details
    CHILD_SA_INFO=$(echo "$SAS_OUTPUT" | grep -- '-tunnel:' | grep -iE "ESTABLISHED|INSTALLED" | head -n 1)

    if [[ -z "$CHILD_SA_INFO" ]]; then echo "Status: No active VPN connection."; exit 0; fi

    ACTIVE_CHILD_NAME=$(echo "$CHILD_SA_INFO" | awk '{print $1}' | sed 's/://')
    VPN_NAME=$(echo "$ACTIVE_CHILD_NAME" | sed 's/-tunnel//')
    UPTIME=$(echo "$CHILD_SA_INFO" | grep -oE '[0-9]+ (second|minute|hour)s? ago' | head -n 1)
    VIRTUAL_IP=$(echo "$SAS_OUTPUT" | grep -A 5 "$ACTIVE_CHILD_NAME" | grep -E '^\s*local\s' | awk '{print $2}' | sed 's/\/32//' | head -n 1)
    
    echo "--- Active VPN Status ---"
    echo "  VPN Name:         $VPN_NAME"; echo "  Status:           ACTIVE"; echo "  Uptime:           ${UPTIME:-unknown}"; echo "  Virtual IP:       ${VIRTUAL_IP:-unknown}"
    echo ""; echo "  Configured Routes:"
    if [[ -z "${VPN_ROUTES[$VPN_NAME]}" ]]; then
        echo "    No specific routes defined for this VPN.";
    else
        for route in ${VPN_ROUTES[$VPN_NAME]}; do
            if ip route show | grep -q "$route"; then echo "    - $route [ACTIVE]"; else echo "    - $route [NOT PRESENT]"; fi
        done
    fi
    echo "------------------------"
}

display_help() {
    echo "IPsec VPN Connection Manager (strongSwan) v5.2"; echo ""
    echo "Usage: $0 <action> [vpn_name]"; echo ""
    echo "Actions:"; echo "  start <vpn_name>  Starts a specific VPN connection."; echo "  stop              Stops the currently active VPN connection."; echo "  status            Shows the status of the active VPN connection."; echo ""
    echo "VPNs defined in '${CONFIG_FILE_LOADED:-No config file found}':"
    if [[ -z "$CONFIG_FILE_LOADED" ]]; then :; else for vpn in "${!VPN_ROUTES[@]}"; do echo "  - $vpn"; done; fi
    echo ""; echo "Examples:"; echo "  $0 start work"; echo "  $0 stop"; echo "  $0 status"; echo ""
}

# --- MAIN LOGIC ---
if [[ $EUID -ne 0 ]]; then echo "ERROR: This script must be run as root (or with sudo)."; exit 1; fi

if [[ -z "$CONFIG_FILE_LOADED" ]] && [[ "$1" != "-h" && "$1" != "--help" && -n "$1" ]]; then
    echo "ERROR: No configuration file found."; echo "        Please create the file in '$USER_CONFIG' or '$SYSTEM_CONFIG'."; exit 1
fi

ACTION="$1"
VPN_NAME="$2"

if [[ "$ACTION" == "start" ]]; then
    NETWORK_DEVICE=$(ip route get 8.8.8.8 | awk --re-interval '{print $5; exit}')
    if [[ -z "$NETWORK_DEVICE" ]]; then echo "ERROR: Could not determine the active network interface."; exit 1; fi
fi

case "$ACTION" in
    start)
        if [[ -z "$VPN_NAME" ]]; then echo "ERROR: The 'start' action requires a VPN name."; display_help; exit 1; fi
        if [[ -z "${VPN_ROUTES[$VPN_NAME]}" ]]; then echo "ERROR: VPN '$VPN_NAME' not found in the configuration file."; display_help; exit 1; fi
        start_vpn
        ;;
    stop) stop_vpn ;;
    status) status_vpn ;;
    -h|--help|'') display_help ;;
    *) echo "ERROR: Action '$ACTION' is not valid."; display_help; exit 1 ;;
esac

exit 0
