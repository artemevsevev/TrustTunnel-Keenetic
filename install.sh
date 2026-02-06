#!/bin/sh

set -e

REPO_URL="https://raw.githubusercontent.com/artemevsevev/TrustTunnel-Keenetic/main"

echo "=== TrustTunnel Keenetic Installer ==="
echo ""

if [ ! -d "/opt" ]; then
    echo "Error: /opt not found. Please install Entware first."
    echo "See: https://help.keenetic.com/hc/en-us/articles/360021214160"
    exit 1
fi

ask_yes_no() {
    printf "%s (y/n) " "$1"
    read answer < /dev/tty
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

# === Mode selection ===
echo "Выберите режим работы TrustTunnel:"
echo "  1) SOCKS5 — проксирование через интерфейс Proxy5 (по умолчанию)"
echo "  2) TUN    — туннель через интерфейс OpkgTun0"
printf "Режим [1]: "
read mode_choice < /dev/tty
case "$mode_choice" in
    2) TT_MODE="tun" ;;
    *) TT_MODE="socks5" ;;
esac
echo "Выбран режим: $TT_MODE"
echo ""

TUN_IP=""
if [ "$TT_MODE" = "tun" ]; then
    if ! command -v ip >/dev/null 2>&1; then
        echo "Error: команда 'ip' не найдена. Установите пакет ip-full:"
        echo "  opkg update && opkg install ip-full"
        exit 1
    fi

    printf "Введите IP-адрес TUN-интерфейса (назначенный VPN-сервером, например 10.0.0.2): "
    read TUN_IP < /dev/tty
    if [ -z "$TUN_IP" ]; then
        echo "Error: IP-адрес не может быть пустым."
        exit 1
    fi
    echo "TUN IP: $TUN_IP"
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
echo "Сохраняю режим в /opt/trusttunnel_client/mode.conf..."
cat > /opt/trusttunnel_client/mode.conf <<MEOF
# TrustTunnel mode: socks5 or tun
TT_MODE="$TT_MODE"
TUN_IP="$TUN_IP"
MEOF
echo "mode.conf сохранён (TT_MODE=$TT_MODE)."

# === Policy + Interface ===
if ask_yes_no "Создать policy TrustTunnel и интерфейс TrustTunnel?"; then

    if [ "$TT_MODE" = "socks5" ]; then
        # --- SOCKS5 Interface ---
        if ndmc -c 'show interface' | grep -q '^Proxy5'; then
            echo "Интерфейс Proxy5 уже существует — пропускаю."
        else
            echo "Создаю интерфейс Proxy5..."
            ndmc -c 'interface Proxy5'
            ndmc -c 'interface Proxy5 description TrustTunnel'
            ndmc -c 'interface Proxy5 dyndns nobind'
            ndmc -c 'interface Proxy5 proxy protocol socks5'
            ndmc -c 'interface Proxy5 proxy upstream 127.0.0.1 1080'
            ndmc -c 'interface Proxy5 proxy connect via ISP'
            ndmc -c 'interface Proxy5 ip global auto'
            ndmc -c 'interface Proxy5 security-level public'
            echo "Интерфейс Proxy5 создан."
        fi

        IFACE_NAME="Proxy5"
    else
        # --- TUN Interface ---
        if ndmc -c 'show interface' | grep -q '^OpkgTun0'; then
            echo "Интерфейс OpkgTun0 уже существует — пропускаю."
        else
            echo "Создаю интерфейс OpkgTun0..."
            ndmc -c 'interface OpkgTun0'
            ndmc -c 'interface OpkgTun0 description TrustTunnel'
            ndmc -c "interface OpkgTun0 ip address $TUN_IP 255.255.255.255"
            ndmc -c 'interface OpkgTun0 ip global auto'
            ndmc -c 'interface OpkgTun0 ip mtu 1500'
            ndmc -c 'interface OpkgTun0 ip tcp adjust-mss pmtu'
            ndmc -c 'interface OpkgTun0 security-level public'
            ndmc -c 'interface OpkgTun0 up'
            echo "Интерфейс OpkgTun0 создан."
        fi

        IFACE_NAME="OpkgTun0"
    fi

    # --- Policy ---
    if ndmc -c 'show ip policy' | grep -q '^TrustTunnel'; then
        echo "Policy TrustTunnel уже существует — пропускаю."
    else
        echo "Создаю ip policy TrustTunnel..."
        ndmc -c 'ip policy TrustTunnel'
        ndmc -c 'ip policy TrustTunnel description TrustTunnel'
        ndmc -c "ip policy TrustTunnel permit global $IFACE_NAME"
        echo "Policy TrustTunnel создана."
    fi

    ndmc -c 'system configuration save'
    echo "Конфигурация сохранена."
else
    echo "Настройка policy и интерфейса пропущена."
fi


# === TrustTunnel install ===
if ask_yes_no "Установить/Обновить TrustTunnel Client?"; then
    echo "Запускаю установку TrustTunnel..."
    curl -fsSL https://raw.githubusercontent.com/TrustTunnel/TrustTunnelClient/refs/heads/master/scripts/install.sh | sh -s -
    echo "Установка TrustTunnel завершена."
else
    echo "Установка TrustTunnel пропущена."
fi

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "1. Create config file /opt/trusttunnel_client/trusttunnel_client.toml"
echo "2. Make binary executable: chmod +x /opt/trusttunnel_client/trusttunnel_client"
if [ "$TT_MODE" = "tun" ]; then
    echo ""
    echo "   В конфигурации клиента добавьте секцию [listener.tun]:"
    echo "   [listener.tun]"
    echo "   included_routes = []"
    echo "   change_system_dns = false"
    echo ""
    echo "   Секции [listener.socks] в файле быть не должно."
fi
echo "3. Start service: /opt/etc/init.d/S99trusttunnel start"
echo ""
