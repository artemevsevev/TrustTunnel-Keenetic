#!/bin/sh

LOG_TAG="TrustTunnel"

sleep 5

logger -t "$LOG_TAG" "WAN interface up, checking TrustTunnel..."

/opt/etc/init.d/S99trusttunnel reload

exit 0
