#!/bin/sh

LOG_TAG="TrustTunnel"
MODE_CONF="/opt/trusttunnel_client/mode.conf"

# Load mode (defaults to socks5)
TT_MODE="socks5"
if [ -f "$MODE_CONF" ]; then
    . "$MODE_CONF"
fi

TUN_IDX="${TUN_IDX:-0}"
OPKG_IFACE="opkgtun${TUN_IDX}"
NDMC_IFACE="OpkgTun${TUN_IDX}"

# Skip reload when triggered by our own TUN interface
# (prevents infinite restart loop when OpkgTun is a default gateway)
if [ "$1" = "$NDMC_IFACE" ]; then
    logger -t "$LOG_TAG" "WAN event for own TUN interface ($1), skipping"
    exit 0
fi

# Skip reload if client was started recently (prevents restart during startup)
START_TS_FILE="/opt/var/run/trusttunnel_start_ts"
GRACE_PERIOD=30
if [ -f "$START_TS_FILE" ]; then
    start_ts=$(cat "$START_TS_FILE" 2>/dev/null)
    now=$(date +%s)
    if [ -n "$start_ts" ] && [ $((now - start_ts)) -lt "$GRACE_PERIOD" ]; then
        logger -t "$LOG_TAG" "Client started ${start_ts:+$((now - start_ts))s ago}, skipping WAN reload"
        exit 0
    fi
fi

sleep 5

logger -t "$LOG_TAG" "WAN interface up, checking TrustTunnel..."

if [ "$TT_MODE" = "tun" ]; then
    logger -t "$LOG_TAG" "TUN mode: bringing down tunnel interfaces before reload..."
    ip link set "$OPKG_IFACE" down 2>/dev/null
    ip link set tun0 down 2>/dev/null
fi

/opt/etc/init.d/S99trusttunnel reload

exit 0
