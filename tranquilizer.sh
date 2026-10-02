#!/bin/bash
#
# Savun Firewall M0E - Полный цикл сборки и доставки
# Собирает лёгкий APK (split-per-abi) → Отправляет файл в Telegram
# → Собирает Web → Разворачивает в app5
#
# Usage: ./tranquilizer.sh [--help|--apk|--web|--all|--light]
#

set -euo pipefail

INVOCATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="$(basename "$INVOCATION_DIR")"

if [ -d "$INVOCATION_DIR/app" ]; then
    PROJECT_DIR="$INVOCATION_DIR/app"
else
    PROJECT_DIR="$INVOCATION_DIR"
fi

FLUTTER="/snap/bin/flutter"

# Чат, куда бот будет присылать файлы
LUCY_PEER_ID="6c065f0f-0b13-576c-9904-659498876464"
LUCY_SEND_URL="http://127.0.0.1:8080/send_peer"

# Определение имени APK
if [ "$PROJECT_NAME" = "M0E" ]; then
    APK_NAME="lucy.apk"
else
    # Приводим к нижнему регистру
    APK_NAME="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]').apk"
fi

# Web
WEB_SRC="$PROJECT_DIR/build/web"
WEB_DST="/var/www/html/${PROJECT_NAME}_web"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ─── Helpers ───────────────────────────────────────────────────────────────────
check_env() {
    local ok=1
    [[ -x "$FLUTTER" ]] || { log_err "Flutter not found: $FLUTTER"; ok=0; }
    [[ -d "$PROJECT_DIR" ]] || { log_err "Project dir not found: $PROJECT_DIR"; ok=0; }
    [[ $ok -eq 1 ]] || exit 1
    export FLUTTER_ROOT="/root/snap/flutter/common/flutter"
    export ANDROID_HOME="/root/android-sdk"
    export PATH="$FLUTTER:$PATH"
}

lucy_send() {
    local text="$1"
    local ts
    ts=$(date +%s%3N)
    local payload="m0e-chat-v1:{\"type\":\"text\",\"text\":\"${text//\"/\\\"}\",\"senderNickname\":\"M0E Tranquilizer\",\"ts\":${ts}}"
    local escaped_payload="${payload//\"/\\\"}"
    curl -s -X POST "$LUCY_SEND_URL" \
        -H "Content-Type: application/json" \
        -d "{\"to_peer_id\": \"${LUCY_PEER_ID}\", \"payload\": \"${escaped_payload}\"}" > /dev/null || true
}

# ─── Стадия 1: APK ────────────────────────────────────────────────────────────
build_apk() {
    log_info "=== СТЭДИЯ 1: Сборка APK ==="
    cd "$PROJECT_DIR"

    # Зависимости
    log_info "flutter pub get..."
    $FLUTTER pub get > /dev/null 2>&1
    log_ok "Зависимости получены"

    # Очистка
    log_info "Очистка..."
    rm -rf build/.dart_tool
    $FLUTTER clean > /dev/null 2>&1
    log_ok "Чисто"

    # Сборка
    log_info "flutter build apk --release (это займёт время)..."
    if ! $FLUTTER build apk --release; then
        log_err "Сборка APK завершилась с ошибкой"
        return 1
    fi

    local apk="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
    if [[ -f "$apk" ]]; then
        local size=$(du -h "$apk" | cut -f1)
        log_ok "APK собран: $apk ($size)"
        echo "$apk"
        return 0
    else
        log_err "APK файл не найден после сборки"
        return 1
    fi
}

build_apk_light() {
    log_info "=== СТЭДИЯ 1: Сборка ЛЁГКОГО APK (split-per-abi) ==="
    cd "$PROJECT_DIR"

    log_info "Очистка (flutter clean)..."
    $FLUTTER clean > /dev/null 2>&1
    log_ok "Чисто (Flutter кэш сброшен)"

    log_info "flutter pub get..."
    $FLUTTER pub get > /dev/null 2>&1
    log_ok "Зависимости получены"

    log_info "flutter build apk --release --split-per-abi ..."
    if ! $FLUTTER build apk --release --split-per-abi; then
        log_err "Сборка лёгкого APK завершилась с ошибкой"
        return 1
    fi

    local apk_arm64="$PROJECT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    [[ -f "$apk_arm64" ]] || { log_err "Не найден $apk_arm64"; return 1; }

    mkdir -p /var/www/html/downloads
    cp -f "$apk_arm64" "/var/www/html/downloads/$APK_NAME"

    local size=$(du -h "$apk_arm64" | cut -f1)
    log_ok "Лёгкий APK собран: $apk_arm64 ($size)"
    echo "$apk_arm64"
}

send_apk_file_to_tg() {
    # Перенаправлено в Люси
    send_apk_file_to_lucy_chat "$1"
}

send_apk_file_to_lucy_chat() {
    local apk="$1"
    local size=$(du -h "$apk" | cut -f1)
    local bytes=$(stat -c%s "$apk" 2>/dev/null || echo "0")
    local filename=$(basename "$apk")
    local download_link="https://0i2.ru/downloads/$APK_NAME"
    local build_date=$(date "+%d.%m.%Y %H:%M")
    local ts
    ts=$(date +%s%3N)

    log_info "Отправка анонса в чат Люси через /send_peer..."
    log_info "  Файл: $filename ($size)"
    log_info "  Ссылка: $download_link"

    local msg_text="🚀 Новая сборка ${PROJECT_NAME} готова! Дата: ${build_date} · ${size}"
    local payload="m0e-chat-v1:{\"type\":\"file\",\"from\":\"server-relay\",\"text\":\"${msg_text}\",\"senderNickname\":\"${PROJECT_NAME} Tranquilizer\",\"download_url\":\"${download_link}\",\"attachment_name\":\"${APK_NAME}\",\"attachment_size\":${bytes},\"attachment_mime\":\"application/vnd.android.package-archive\",\"ts\":${ts}}"
    local escaped_payload="${payload//\"/\\\"}"

    local response
    response=$(curl -s -X POST "$LUCY_SEND_URL" \
        -H "Content-Type: application/json" \
        -d "{\"to_peer_id\": \"${LUCY_PEER_ID}\", \"from_peer_id\": \"server-relay\", \"payload\": \"${escaped_payload}\"}") || true

    if echo "$response" | grep -q '"ok":true'; then
        log_ok "Уведомление доставлено в чат Люси"
    else
        log_warn "Люси офлайн — сообщение добавлено в очередь: $response"
    fi
}


send_apk_to_tg() {
    local apk="$1"
    local size=$(du -h "$apk" | cut -f1)

    log_info "Отправка APK в чат Люси..."
    log_info "  Файл: $(basename $apk)"
    log_info "  Размер: $size"

    local txt="📦 Savun Firewall M0E — APK собран\n\n"
    txt+="💾 Размер: ${size}\n"
    txt+="📁 Путь: ${apk}\n"

    lucy_send "$txt"
    log_ok "Уведомление отправлено в чат Люси"
}

# ─── Стадия 2: Web ────────────────────────────────────────────────────────────
build_web() {
    log_info "=== СТЭДИЯ 2: Сборка Web ==="
    cd "$PROJECT_DIR"

    log_info "Очистка старого web-сборки..."
    rm -rf "$WEB_SRC"

    log_info "flutter build web --release --no-tree-shake-icons --base-href /app5/ ..."
    if ! $FLUTTER build web --release --no-tree-shake-icons --base-href /app5/; then
        log_err "Сборка web завершилась с ошибкой"
        return 1
    fi

    if [[ ! -f "$WEB_SRC/index.html" && -f "$PROJECT_DIR/web/index.html" ]]; then
        cp "$PROJECT_DIR/web/index.html" "$WEB_SRC/index.html"
    fi

    if [[ -f "$WEB_SRC/index.html" ]]; then
        local size=$(du -sh "$WEB_SRC" | cut -f1)
        local cnt=$(find "$WEB_SRC" -type f | wc -l)
        log_ok "Web собран: $size, $cnt файлов"
        return 0
    else
        log_err "index.html не найден после сборки web"
        return 1
    fi
}

deploy_web() {
    log_info "=== СТЭДИЯ 3: Развёртывание Web в app5 ==="

    # Бэкап текущего
    if [[ -d "$WEB_DST" ]] && [[ "$(ls -A $WEB_DST 2>/dev/null)" ]]; then
        log_info "Бэкап текущей версии..."
        rm -rf "${WEB_DST}.backup"
        mv "$WEB_DST" "${WEB_DST}.backup"
    fi

    # Копируем новую
    mkdir -p "$WEB_DST"
    cp -r "$WEB_SRC"/* "$WEB_DST"/

    # Автоматический патч обхода кэша и удаления Service Worker
    log_info "Патчим кэширование и Service Worker..."
    python3 -c "
import pathlib, re
idx = pathlib.Path('$WEB_DST/index.html')
if idx.exists():
    idx.write_text(idx.read_text().replace('<head>', '<head><script>if(\"serviceWorker\" in navigator){navigator.serviceWorker.getRegistrations().then(function(regs){for(var i=0;i<regs.length;i++){regs[i].unregister().then(function(ok){if(ok)window.location.reload();});}})}</script>').replace('flutter_bootstrap.js', 'flutter_bootstrap.js?v=2'))
boot = pathlib.Path('$WEB_DST/flutter_bootstrap.js')
if boot.exists():
    txt = boot.read_text().replace('\"main.dart.js\"', '\"main.dart.js?v=2\"')
    txt = re.sub(r'serviceWorkerSettings:\s*\{[^}]*\}', 'serviceWorkerSettings: null', txt)
    boot.write_text(txt)
"

    chown -R www-data:www-data "$WEB_DST"
    chmod -R 755 "$WEB_DST"
    log_ok "Файлы скопированы в $WEB_DST"

    # Проверяем конфиг Nginx
    nginx -t > /dev/null 2>&1 || { log_err "Ошибка в конфиге Nginx"; return 1; }

    # Перезапуск
    log_info "Перезапуск Nginx..."
    nginx -s reload > /dev/null 2>&1
    sleep 1

    # Проверка доступности
    local code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/app5/)
    if [[ "$code" == "200" ]]; then
        log_ok "Web доступен: http://localhost/app5/ (HTTP 200)"
        rm -rf "${WEB_DST}.backup" 2>/dev/null
    else
        log_warn "Web вернул HTTP $code, возможна задержка"
        # Восстанавливаем бэкап только если совсем плохо
        if [[ "$code" =~ ^5 ]]; then
            log_err "Ошибка 5xx, откат..."
            rm -rf "$WEB_DST"
            mv "${WEB_DST}.backup" "$WEB_DST" 2>/dev/null
            nginx -s reload > /dev/null 2>&1
            return 1
        fi
    fi
    # Cleanup excessive Gradle build caches to protect disk space
    rm -rf /root/.gradle/caches/build-cache-1 /root/.gradle/caches/8.14 /root/.gradle/caches/9.1.0 2>/dev/null || true
    return 0
}

# ─── Главная функция ─────────────────────────────────────────────────────────
main() {
    local mode="${1:---all}"

    case "$mode" in
        --light|light)
            check_env
            local light_apk
            light_apk=$(build_apk_light | tail -n 1) && send_apk_file_to_lucy_chat "$light_apk"
            ;;
        --apk|apk)
            check_env
            local light_apk
            light_apk=$(build_apk_light | tail -n 1) && send_apk_file_to_lucy_chat "$light_apk"
            ;;
        --web|web)
            check_env
            build_web && deploy_web
            ;;
        --all|all|"")
            echo ""
            echo "  Savun Firewall M0E — Полный цикл сборки"
            echo "  $(date)"
            echo ""
            check_env

            # 1. Лёгкий APK
            local light_apk
            light_apk=$(build_apk_light | tail -n 1) && send_apk_file_to_lucy_chat "$light_apk"

            # 2. Web
            build_web && deploy_web

            echo ""
            log_ok "ВСЁ ГОТОВО!"
            log_info "APK:  $PROJECT_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
            log_info "Web:  http://localhost/app5/"
            echo ""
            ;;
        --help|-h)
            echo "Использование: $0 [--apk|--web|--all|--light]"
            echo "  --apk   Собрать лёгкий APK (split-per-abi) и отправить файл в Telegram"
            echo "  --light То же, что --apk"
            echo "  --web   Собрать и развернуть только Web"
            echo "  --all   Полный цикл (по умолчанию)"
            ;;
        *)
            log_err "Неизвестный режим: $mode"
            exit 1
            ;;
    esac
}

main "$@"
