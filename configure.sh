#!/bin/sh

set -e
# Uncomment for debugging:
# set -x

# REPO_URL передаётся из install.sh через переменную окружения
if [ -z "$REPO_URL" ]; then
    echo "Ошибка: REPO_URL не задан. Запустите install.sh."
    exit 1
fi

cleanup_on_error() {
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "!!! Установка прервана из-за ошибки (код: $exit_code) !!!"
        echo "Для повторной установки запустите скрипт заново."
        echo "Для очистки вручную удалите:"
        echo "  rm -f /opt/etc/init.d/S99trusttunnel"
        echo "  rm -f /opt/etc/ndm/wan.d/010-trusttunnel.sh"
        echo "  rm -f /opt/trusttunnel_client/mode.conf"
    fi
}
trap cleanup_on_error EXIT

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

    echo "Обнаружены существующие ${_fi_prefix}-интерфейсы:"
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
echo "Выберите режим работы TrustTunnel:"
echo "  1) SOCKS5 — проксирование через интерфейс Proxy (по умолчанию)"
echo "  2) TUN    — туннель через интерфейс OpkgTun (только для прошивки 5.x)"
printf "Режим [1]: "
read mode_choice < /dev/tty
case "$mode_choice" in
    2) TT_MODE="tun" ;;
    *) TT_MODE="socks5" ;;
esac
echo "Выбран режим: $TT_MODE"
echo ""

TUN_IP="172.16.219.2"
TUN_IPV6="fd01::2"
if [ "$TT_MODE" = "tun" ]; then
    if ! command -v ip >/dev/null 2>&1; then
        echo "Ошибка: команда 'ip' не найдена. Установите пакет ip-full:"
        echo "  opkg update && opkg install ip-full"
        exit 1
    fi
    echo "TUN IP: $TUN_IP"
    echo "TUN IPv6: $TUN_IPV6"
    echo ""

    find_free_index "OpkgTun" "$EXISTING_TUN_IDX"

    printf "Индекс TUN-интерфейса OpkgTun (по умолчанию %s): " "$default_idx"
    read tun_idx_input < /dev/tty
    TUN_IDX="${tun_idx_input:-$default_idx}"
    case "$TUN_IDX" in
        ''|*[!0-9]*)
            echo "Ошибка: индекс должен быть неотрицательным числом."
            exit 1 ;;
    esac
    echo "Интерфейс: OpkgTun${TUN_IDX} (opkgtun${TUN_IDX})"
    echo ""
    PROXY_IDX="${EXISTING_PROXY_IDX:-0}"
else
    TUN_IDX="${EXISTING_TUN_IDX:-0}"

    find_free_index "Proxy" "$EXISTING_PROXY_IDX"

    printf "Индекс интерфейса Proxy (по умолчанию %s): " "$default_idx"
    read proxy_idx_input < /dev/tty
    PROXY_IDX="${proxy_idx_input:-$default_idx}"
    case "$PROXY_IDX" in
        ''|*[!0-9]*)
            echo "Ошибка: индекс должен быть неотрицательным числом."
            exit 1 ;;
    esac
    echo "Интерфейс: Proxy${PROXY_IDX}"
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
echo "mode.conf сохранён (TT_MODE=$TT_MODE)."

# === Interface ===
if ask_yes_no "Создать интерфейс TrustTunnel?"; then

    if ! command -v ndmc >/dev/null 2>&1; then
        echo "Ошибка: команда 'ndmc' не найдена. Настройка интерфейсов невозможна."
        echo "Настройте интерфейс вручную через веб-интерфейс роутера."
    else
        ndmc_iface_output=$(ndmc -c 'show interface' 2>&1) || {
            echo "Ошибка: не удалось получить список интерфейсов от ndmc."
            echo "Настройте интерфейс вручную через веб-интерфейс роутера."
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
                echo "Удаляю старый интерфейс ${OLD_IFACE_NAME}..."
                ndmc -c "no interface ${OLD_IFACE_NAME}" || true
            fi

            if [ "$TT_MODE" = "socks5" ]; then
                # --- SOCKS5 Interface ---
                if echo "$ndmc_iface_output" | grep -q "^Proxy${PROXY_IDX}"; then
                    echo "Интерфейс Proxy${PROXY_IDX} уже существует — пропускаю."
                else
                    echo "Создаю интерфейс Proxy${PROXY_IDX}..."
                    ndmc -c "interface Proxy${PROXY_IDX}"
                    ndmc -c "interface Proxy${PROXY_IDX} description TrustTunnel-${PROXY_IDX}"
                    ndmc -c "interface Proxy${PROXY_IDX} proxy protocol socks5"
                    ndmc -c "interface Proxy${PROXY_IDX} proxy upstream 127.0.0.1 1080"
                    ndmc -c "interface Proxy${PROXY_IDX} proxy connect via ISP"
                    ndmc -c "interface Proxy${PROXY_IDX} ip global auto"
                    ndmc -c "interface Proxy${PROXY_IDX} security-level public"
                    echo "Интерфейс Proxy${PROXY_IDX} создан."
                fi

            else
                # --- TUN Interface ---
                if echo "$ndmc_iface_output" | grep -q "^${NDMC_IFACE}"; then
                    echo "Интерфейс ${NDMC_IFACE} уже существует — пропускаю."
                else
                    echo "Создаю интерфейс ${NDMC_IFACE}..."
                    ndmc -c "interface ${NDMC_IFACE}"
                    ndmc -c "interface ${NDMC_IFACE} description TrustTunnel-${TUN_IDX}"
                    ndmc -c "interface ${NDMC_IFACE} ip global auto"
                    ndmc -c "interface ${NDMC_IFACE} ip address $TUN_IP 255.255.255.255"
                    ndmc -c "interface ${NDMC_IFACE} ipv6 address $TUN_IPV6"
                    ndmc -c "interface ${NDMC_IFACE} ip mtu 1280"
                    ndmc -c "interface ${NDMC_IFACE} ip tcp adjust-mss pmtu"
                    ndmc -c "interface ${NDMC_IFACE} security-level public"
                    ndmc -c "interface ${NDMC_IFACE} up"
                    echo "Интерфейс ${NDMC_IFACE} создан."
                fi

            fi

            ndmc -c 'system configuration save'
            echo "Конфигурация сохранена."
        fi
    fi
else
    echo "Настройка интерфейса пропущена."
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
echo ""
echo "2. Запустите сервис: /opt/etc/init.d/S99trusttunnel start"
echo ""

exit 0
