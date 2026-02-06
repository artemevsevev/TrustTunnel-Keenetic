#!/bin/sh

LOG_TAG="TrustTunnel"
MODE_CONF="/opt/trusttunnel_client/mode.conf"

# Load mode (defaults to socks5)
TT_MODE="socks5"
if [ -f "$MODE_CONF" ]; then
    . "$MODE_CONF"
fi

sleep 5

logger -t "$LOG_TAG" "WAN interface up, checking TrustTunnel..."

if [ "$TT_MODE" = "tun" ]; then
    logger -t "$LOG_TAG" "TUN mode: bringing down tunnel interfaces before reload..."
    ip link set opkgtun0 down 2>/dev/null
    ip link set tun0 down 2>/dev/null
fi

/opt/etc/init.d/S99trusttunnel reload

exit 0
