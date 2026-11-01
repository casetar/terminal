#!/bin/bash
set -e

PROJECT_DIR="/root/vpngate_flutter/savun"
cd "$PROJECT_DIR"

export JAVA_TOOL_OPTIONS="-Xms256m -Xmx2048m"

echo "=== [1/3] Building Release APK ==="
flutter build apk --release --split-per-abi --no-tree-shake-icons

APK_PATH="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
if [ ! -f "$APK_PATH" ]; then
    APK_PATH=$(find build/app/outputs/flutter-apk -name "*release*.apk" | head -n 1)
fi

if [ ! -f "$APK_PATH" ]; then
    echo "❌ Ошибка: APK файл не найден!"
    exit 1
fi

SIZE=$(du -h "$APK_PATH" | cut -f1)
BYTES=$(stat -c%s "$APK_PATH" 2>/dev/null || echo "0")
BUILD_DATE=$(date "+%d.%m.%Y %H:%M")

echo "=== [2/3] Publishing APK to web downloads ==="
mkdir -p /var/www/html/downloads
DEST_APK="/var/www/html/downloads/savun.apk"
cp -f "$APK_PATH" "$DEST_APK"
chmod 644 "$DEST_APK"

DOWNLOAD_LINK="https://0i2.ru/downloads/savun.apk"
echo "✅ APK опубликован: $DOWNLOAD_LINK (Размер: $SIZE, $BYTES байт)"

echo "=== [3/3] Sending APK card to Lucy Chat ==="
python3 -c "
import urllib.request, json, time

peer_id = '6c065f0f-0b13-576c-9904-659498876464'
url = 'http://127.0.0.1:8080/send_peer'
apk_url = '$DOWNLOAD_LINK'
size = '$SIZE'
bytes_sz = int('$BYTES') if '$BYTES'.isdigit() else 0
ts = int(time.time() * 1000)

msg_text = f'🚀 Новая сборка Savun готова! Дата: $BUILD_DATE · {size}\n📥 Скачать: {apk_url}'
payload = 'm0e-chat-v1:' + json.dumps({
    'type': 'chat',
    'msgId': f'savun-{ts}',
    'text': msg_text,
    'senderNickname': 'Savun Pipeline',
    'timestamp': ts,
    'download_url': apk_url,
    'attachment_name': 'savun.apk',
    'attachment_size': bytes_sz
}, ensure_ascii=False)

req_data = json.dumps({
    'to_peer_id': peer_id,
    'from_peer_id': 'server-relay',
    'payload': payload
}).encode('utf-8')

try:
    req = urllib.request.Request(url, data=req_data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as resp:
        print('Отправка в Lucy:', resp.read().decode())
except Exception as e:
    print('Ошибка отправки в Lucy:', e)
"

echo "🎉 Сборка Savun и отправка в Lucy успешно завершены!"
