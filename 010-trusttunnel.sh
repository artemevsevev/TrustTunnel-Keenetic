#!/bin/sh

LOG_FILE="/opt/var/log/trusttunnel.log"

sleep 5

echo "$(date): WAN interface up, checking TrustTunnel..." >> "$LOG_FILE"

/opt/etc/init.d/S99trusttunnel reload

exit 0
