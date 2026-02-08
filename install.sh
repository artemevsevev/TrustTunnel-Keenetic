#!/bin/sh

set -e

GITHUB_REPO="artemevsevev/TrustTunnel-Keenetic"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}"
FALLBACK_REF="main"

# --- Определение версии ---
RELEASE_TAG=""

# Поддержка флага --version <tag>
while [ $# -gt 0 ]; do
    case "$1" in
        --dev)
            RELEASE_TAG="main"
            shift
            ;;
        --version)
            shift
            RELEASE_TAG="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ -n "$RELEASE_TAG" ]; then
    echo "Указана версия: ${RELEASE_TAG}"
else
    # Автоопределение последнего релиза через GitHub API
    API_RESPONSE=$(curl -fsSL --connect-timeout 10 --max-time 15 \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) || API_RESPONSE=""
    RELEASE_TAG=$(echo "$API_RESPONSE" | grep '"tag_name"' | \
        sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

if [ -n "$RELEASE_TAG" ]; then
    REPO_URL="${RAW_BASE}/${RELEASE_TAG}"
    echo "=== Установщик TrustTunnel для Keenetic (${RELEASE_TAG}) ==="
else
    echo "Внимание: не удалось определить последний релиз. Используется ветка ${FALLBACK_REF}."
    REPO_URL="${RAW_BASE}/${FALLBACK_REF}"
    echo "=== Установщик TrustTunnel для Keenetic (${FALLBACK_REF}) ==="
fi
echo ""

# --- Скачиваем и запускаем configure.sh из релиза ---
CONFIGURE_SCRIPT=$(mktemp /tmp/tt_configure.XXXXXX)
trap "rm -f '$CONFIGURE_SCRIPT'" EXIT

echo "Скачиваю скрипт конфигурации..."
curl -fsSL "$REPO_URL/configure.sh" -o "$CONFIGURE_SCRIPT"
chmod +x "$CONFIGURE_SCRIPT"

REPO_URL="$REPO_URL" sh "$CONFIGURE_SCRIPT"
