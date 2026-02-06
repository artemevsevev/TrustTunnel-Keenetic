#!/bin/sh

set -e

cleanup_on_error() {
    echo ""
    echo "!!! Установка прервана из-за ошибки !!!"
    echo "Для повторной установки запустите скрипт заново."
    echo "Для очистки вручную удалите:"
    echo "  rm -f /opt/etc/init.d/S99trusttunnel"
    echo "  rm -f /opt/etc/ndm/wan.d/010-trusttunnel.sh"
    echo "  rm -rf /opt/trusttunnel_client"
}
trap cleanup_on_error ERR

REPO_URL="https://raw.githubusercontent.com/artemevsevev/TrustTunnel-Keenetic/main"

echo "=== Установщик TrustTunnel для Keenetic ==="
echo ""

if [ ! -d "/opt" ]; then
    echo "Ошибка: /opt не найден. Сначала установите Entware."
    echo "Подробнее: https://help.keenetic.com/hc/en-us/articles/360021214160"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Ошибка: команда 'curl' не найдена. Установите пакет curl:"
    echo "  opkg update && opkg install curl"
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
echo "  2) TUN    — туннель через интерфейс OpkgTun0 (только для прошивки 5.x)"
printf "Режим [1]: "
read mode_choice < /dev/tty
case "$mode_choice" in
    2) TT_MODE="tun" ;;
    *) TT_MODE="socks5" ;;
esac
echo "Выбран режим: $TT_MODE"
echo ""

TUN_IP="172.16.219.2"
if [ "$TT_MODE" = "tun" ]; then
    if ! command -v ip >/dev/null 2>&1; then
        echo "Ошибка: команда 'ip' не найдена. Установите пакет ip-full:"
        echo "  opkg update && opkg install ip-full"
        exit 1
    fi
    echo "TUN IP: $TUN_IP"
    echo ""
fi

echo "Создаю директории..."
mkdir -p /opt/etc/init.d
mkdir -p /opt/etc/ndm/wan.d
mkdir -p /opt/var/run
mkdir -p /opt/var/log
mkdir -p /opt/trusttunnel_client

echo "Скачиваю S99trusttunnel..."
curl -fsSL "$REPO_URL/S99trusttunnel" -o /opt/etc/init.d/S99trusttunnel
chmod +x /opt/etc/init.d/S99trusttunnel

echo "Скачиваю 010-trusttunnel.sh..."
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

    if ! command -v ndmc >/dev/null 2>&1; then
        echo "Ошибка: команда 'ndmc' не найдена. Настройка интерфейсов невозможна."
        echo "Настройте интерфейс и policy вручную через веб-интерфейс роутера."
    else
        ndmc_iface_output=$(ndmc -c 'show interface' 2>&1) || {
            echo "Ошибка: не удалось получить список интерфейсов от ndmc."
            echo "Настройте интерфейс и policy вручную через веб-интерфейс роутера."
            ndmc_iface_output=""
        }

        if [ -n "$ndmc_iface_output" ]; then
            if [ "$TT_MODE" = "socks5" ]; then
                # --- SOCKS5 Interface ---
                if echo "$ndmc_iface_output" | grep -q '^Proxy5'; then
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
                if echo "$ndmc_iface_output" | grep -q '^OpkgTun0'; then
                    echo "Интерфейс OpkgTun0 уже существует — пропускаю."
                else
                    echo "Создаю интерфейс OpkgTun0..."
                    ndmc -c 'interface OpkgTun0'
                    ndmc -c 'interface OpkgTun0 description TrustTunnel'
                    ndmc -c "interface OpkgTun0 ip address $TUN_IP 255.255.255.255"
                    ndmc -c 'interface OpkgTun0 ip global auto'
                    ndmc -c 'interface OpkgTun0 ip mtu 1280'
                    ndmc -c 'interface OpkgTun0 ip tcp adjust-mss pmtu'
                    ndmc -c 'interface OpkgTun0 security-level public'
                    ndmc -c 'interface OpkgTun0 up'
                    echo "Интерфейс OpkgTun0 создан."
                fi

                IFACE_NAME="OpkgTun0"
            fi

            # --- Policy ---
            ndmc_policy_output=$(ndmc -c 'show ip policy' 2>&1) || ndmc_policy_output=""
            if [ -n "$ndmc_policy_output" ] && echo "$ndmc_policy_output" | grep -q '^TrustTunnel'; then
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
        fi
    fi
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
echo "=== Установка завершена ==="
echo ""
echo "Дальнейшие шаги:"
echo "1. Создайте файл конфигурации /opt/trusttunnel_client/trusttunnel_client.toml"
echo "2. Сделайте бинарник исполняемым: chmod +x /opt/trusttunnel_client/trusttunnel_client"
if [ "$TT_MODE" = "tun" ]; then
    echo ""
    echo "   В конфигурации клиента добавьте секцию [listener.tun]:"
    echo "   [listener.tun]"
    echo "   included_routes = []"
    echo "   change_system_dns = false"
    echo ""
    echo "   Секции [listener.socks] в файле быть не должно."
else
    echo ""
    echo "   В конфигурации клиента должна быть секция [listener.socks]."
    echo "   Секции [listener.tun] в файле быть не должно."
fi
echo "3. Запустите сервис: /opt/etc/init.d/S99trusttunnel start"
echo ""
