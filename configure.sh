#!/bin/sh

set -e
# Uncomment for debugging:
# set -x

# REPO_URL is passed from install.sh via environment variable
if [ -z "$REPO_URL" ]; then
    echo "Error: REPO_URL is not set. Run install.sh."
    exit 1
fi

cleanup_on_error() {
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "!!! Installation aborted due to error (code: $exit_code) !!!"
        echo "To reinstall, run the script again."
        echo "To clean up manually, delete:"
        echo "  rm -f /opt/etc/init.d/S99trusttunnel"
        echo "  rm -f /opt/etc/ndm/wan.d/010-trusttunnel.sh"
        echo "  rm -f /opt/trusttunnel_client/mode.conf"
    fi
}
trap cleanup_on_error EXIT

if [ ! -d "/opt" ]; then
    echo "Error: /opt not found. Install Entware first."
    echo "Details: https://help.keenetic.com/hc/en-us/articles/360021214160"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Error: 'curl' command not found. Install curl package:"
    echo "  opkg update && opkg install curl"
    exit 1
fi

ask_yes_no() {
    printf "%s (y/n) " "$1"
    read answer < /dev/tty || return 1
    case "$answer" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

# === Stop running service ===
INIT_SCRIPT="/opt/etc/init.d/S99trusttunnel"
if [ -x "$INIT_SCRIPT" ]; then
    echo "Stopping TrustTunnel..."
    "$INIT_SCRIPT" stop || true
fi

# Find first free interface index by prefix
# Usage: find_free_index <prefix> <existing_idx>
# Sets shell variable: default_idx
find_free_index() {
    _fi_prefix="$1"
    _fi_existing="$2"

    if [ -n "$_fi_existing" ]; then
        default_idx="$_fi_existing"
    else
        default_idx="0"
    fi

    if ! command -v ndmc >/dev/null 2>&1; then
        return 0
    fi

    _fi_scan=$(ndmc -c 'show interface' 2>/dev/null) || return 0
    [ -n "$_fi_scan" ] || return 0

    _fi_used=$(echo "$_fi_scan" | grep -E "${_fi_prefix}[0-9]+" | sed -E "s/.*${_fi_prefix}([0-9]+).*/\1/" | sort -nu || true)

    # If no interfaces found, just return with default_idx already set
    if [ -z "$_fi_used" ]; then
        return 0
    fi

    echo "Discovered existing ${_fi_prefix}-interfaces:"
    echo "$_fi_scan" | { grep -E "${_fi_prefix}[0-9]+" || true; } | while read -r _fi_line; do
        echo "  $_fi_line"
    done
    echo ""

    if [ -z "$_fi_existing" ]; then
        _fi_next=0
        for _fi_idx in $_fi_used; do
            if [ "$_fi_next" -eq "$_fi_idx" ]; then
                _fi_next=$((_fi_next + 1))
            fi
        done
        default_idx="$_fi_next"
    fi

    return 0
}

# === Read existing config ===
EXISTING_TUN_IDX=""
EXISTING_PROXY_IDX=""
EXISTING_MODE=""
if [ -f /opt/trusttunnel_client/mode.conf ]; then
    . /opt/trusttunnel_client/mode.conf
    EXISTING_TUN_IDX="${TUN_IDX:-0}"
    EXISTING_PROXY_IDX="${PROXY_IDX:-0}"
    EXISTING_MODE="${TT_MODE:-socks5}"
fi

# === Mode selection ===
if [ "$EXISTING_MODE" = "tun" ]; then
    default_mode=2
else
    default_mode=1
fi
echo "Select TrustTunnel operation mode:"
echo "  1) SOCKS5 - proxying through Proxy interface"
echo "  2) TUN    - tunnel through OpkgTun interface (only for firmware 5.x)"
printf "Mode [%s]: " "$default_mode"
read mode_choice < /dev/tty
mode_choice="${mode_choice:-$default_mode}"
case "$mode_choice" in
    2) TT_MODE="tun" ;;
    *) TT_MODE="socks5" ;;
esac
echo "Selected mode: $TT_MODE"
echo ""

TUN_IP="172.16.219.2"
TUN_IPV6="fd01::2"
if [ "$TT_MODE" = "tun" ]; then
    if ! command -v ip >/dev/null 2>&1; then
        echo "Error: 'ip' command not found. Install ip-full package:"
        echo "  opkg update && opkg install ip-full"
        exit 1
    fi
    echo "TUN IP: $TUN_IP"
    echo "TUN IPv6: $TUN_IPV6"
    echo ""

    find_free_index "OpkgTun" "$EXISTING_TUN_IDX"

    printf "OpkgTun interface index (default %s): " "$default_idx"
    read tun_idx_input < /dev/tty
    TUN_IDX="${tun_idx_input:-$default_idx}"
    case "$TUN_IDX" in
        ''|*[!0-9]*)
            echo "Error: index must be a non-negative number."
            exit 1 ;;
    esac
    echo "Interface: OpkgTun${TUN_IDX} (opkgtun${TUN_IDX})"
    echo ""
    PROXY_IDX="${EXISTING_PROXY_IDX:-0}"
else
    TUN_IDX="${EXISTING_TUN_IDX:-0}"

    find_free_index "Proxy" "$EXISTING_PROXY_IDX"

    printf "Proxy interface index (default %s): " "$default_idx"
    read proxy_idx_input < /dev/tty
    PROXY_IDX="${proxy_idx_input:-$default_idx}"
    case "$PROXY_IDX" in
        ''|*[!0-9]*)
            echo "Error: index must be a non-negative number."
            exit 1 ;;
    esac
    echo "Interface: Proxy${PROXY_IDX}"
    echo ""
fi

echo "Creating directories..."
mkdir -p /opt/etc/init.d
mkdir -p /opt/etc/ndm/wan.d
mkdir -p /opt/var/run
mkdir -p /opt/var/log
mkdir -p /opt/trusttunnel_client

echo "Downloading S99trusttunnel..."
curl -fsSL "$REPO_URL/S99trusttunnel" -o /opt/etc/init.d/S99trusttunnel
chmod +x /opt/etc/init.d/S99trusttunnel

echo "Downloading 010-trusttunnel.sh..."
curl -fsSL "$REPO_URL/010-trusttunnel.sh" -o /opt/etc/ndm/wan.d/010-trusttunnel.sh
chmod +x /opt/etc/ndm/wan.d/010-trusttunnel.sh

# === Write mode.conf ===
echo "Saving mode to /opt/trusttunnel_client/mode.conf..."
cat > /opt/trusttunnel_client/mode.conf <<MEOF
# TrustTunnel mode: socks5 or tun
TT_MODE="$TT_MODE"
TUN_IP="$TUN_IP"
TUN_IPV6="$TUN_IPV6"
TUN_IDX="$TUN_IDX"
PROXY_IDX="$PROXY_IDX"

# Health check settings (uncomment to customize)
# HC_ENABLED="yes"
# HC_INTERVAL=30
# HC_FAIL_THRESHOLD=3
# HC_GRACE_PERIOD=60
# HC_TARGET_URL="http://connectivitycheck.gstatic.com/generate_204"
# HC_CURL_TIMEOUT=5
# HC_SOCKS5_PROXY="127.0.0.1:1080"
MEOF
echo "mode.conf saved (TT_MODE=$TT_MODE)."

# === Interface ===
if ask_yes_no "Create TrustTunnel interface?"; then

    if ! command -v ndmc >/dev/null 2>&1; then
        echo "Error: 'ndmc' command not found. Interface configuration is not possible."
        echo "Configure the interface manually via the router's web interface."
    else
        ndmc_iface_output=$(ndmc -c 'show interface' 2>&1) || {
            echo "Error: failed to get interface list from ndmc."
            echo "Configure the interface manually via the router's web interface."
            ndmc_iface_output=""
        }

        if [ -n "$ndmc_iface_output" ]; then
            # Determine old interface name for cleanup
            OLD_IFACE_NAME=""
            if [ -n "$EXISTING_MODE" ]; then
                if [ "$EXISTING_MODE" = "tun" ]; then
                    OLD_IFACE_NAME="OpkgTun${EXISTING_TUN_IDX}"
                else
                    OLD_IFACE_NAME="Proxy${EXISTING_PROXY_IDX}"
                fi
            fi

            # Remove old interface if index or mode changed
            NDMC_IFACE="OpkgTun${TUN_IDX}"
            if [ "$TT_MODE" = "socks5" ]; then
                IFACE_NAME="Proxy${PROXY_IDX}"
            else
                IFACE_NAME="${NDMC_IFACE}"
            fi
            if [ -n "$OLD_IFACE_NAME" ] && [ "$OLD_IFACE_NAME" != "$IFACE_NAME" ]; then
                echo "Removing old interface ${OLD_IFACE_NAME}..."
                ndmc -c "no interface ${OLD_IFACE_NAME}" || true
            fi

            if [ -n "$OLD_IFACE_NAME" ] && [ "$OLD_IFACE_NAME" = "$IFACE_NAME" ]; then
                # Interface already configured — skip creation, just ensure default route
                echo "Interface ${IFACE_NAME} is already configured, skipping creation."
                if [ "$TT_MODE" = "tun" ]; then
                    ndmc -c "ip route default $TUN_IP ${NDMC_IFACE}"
                    ndmc -c "ipv6 route default ${NDMC_IFACE}"
                fi
            elif [ "$TT_MODE" = "socks5" ]; then
                # --- SOCKS5 Interface ---
                echo "Configuring Proxy${PROXY_IDX} interface..."
                ndmc -c "interface Proxy${PROXY_IDX}"
                ndmc -c "interface Proxy${PROXY_IDX} description \"TrustTunnel Proxy ${PROXY_IDX}\""
                ndmc -c "interface Proxy${PROXY_IDX} proxy protocol socks5"
                ndmc -c "interface Proxy${PROXY_IDX} proxy upstream 127.0.0.1 1080"
                ndmc -c "interface Proxy${PROXY_IDX} proxy connect"
                ndmc -c "interface Proxy${PROXY_IDX} ip global auto"
                ndmc -c "interface Proxy${PROXY_IDX} security-level public"
                echo "Proxy${PROXY_IDX} interface configured."
            else
                # --- TUN Interface ---
                echo "Configuring ${NDMC_IFACE} interface..."
                ndmc -c "interface ${NDMC_IFACE}"
                ndmc -c "interface ${NDMC_IFACE} description \"TrustTunnel TUN ${TUN_IDX}\""
                ndmc -c "interface ${NDMC_IFACE} ip address $TUN_IP 255.255.255.255"
                ndmc -c "interface ${NDMC_IFACE} ipv6 address $TUN_IPV6"
                ndmc -c "interface ${NDMC_IFACE} ip global auto"
                ndmc -c "interface ${NDMC_IFACE} ip mtu 1280"
                ndmc -c "interface ${NDMC_IFACE} ip tcp adjust-mss pmtu"
                ndmc -c "interface ${NDMC_IFACE} security-level public"
                ndmc -c "interface ${NDMC_IFACE} up"
                ndmc -c "ip route default $TUN_IP ${NDMC_IFACE}"
                ndmc -c "ipv6 route default ${NDMC_IFACE}"
                echo "${NDMC_IFACE} interface configured."
            fi

            ndmc -c 'system configuration save'
            echo "Configuration saved."
        fi
    fi
else
    echo "Interface configuration skipped."
fi


# === TrustTunnel install ===
if ask_yes_no "Install/Update TrustTunnel Client?"; then
    echo "Starting TrustTunnel installation..."
    curl -fsSL https://raw.githubusercontent.com/TrustTunnel/TrustTunnelClient/refs/heads/master/scripts/install.sh | sh -s -
    echo "TrustTunnel installation completed."
else
    echo "TrustTunnel installation skipped."
fi

echo ""
echo "=== Installation completed ==="
echo ""
echo "Next steps:"
echo "1. Create a configuration file /opt/trusttunnel_client/trusttunnel_client.toml"
if [ "$TT_MODE" = "tun" ]; then
    echo ""
    echo "   Add the [listener.tun] section to the client configuration:"
    echo "   [listener.tun]"
    echo "   included_routes = []"
    echo "   excluded_routes = []"
    echo "   change_system_dns = false"
    echo ""
    echo "   The [listener.socks] section should not be in the file."
else
    echo ""
    echo "   The client configuration must contain the [listener.socks] section."
    echo "   The [listener.tun] section should not be in the file."
fi
echo ""
echo "2. Start the service: /opt/etc/init.d/S99trusttunnel start"
echo ""

exit 0
