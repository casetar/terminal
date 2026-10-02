#!/bin/bash
apk="build/app/outputs/flutter-apk/app-release.apk"
size=$(du -h "$apk" | cut -f1)
bytes=$(stat -c%s "$apk" 2>/dev/null || echo "0")
cp -f "$apk" /var/www/html/downloads/savun.apk
download_link="https://0i2.ru/downloads/savun.apk"
build_date=$(date "+%d.%m.%Y %H:%M")
ts=$(date +%s%3N)
LUCY_PEER_ID="fa7206de-6a28-435d-847a-8bb5edd17af6"
LUCY_SEND_URL="http://127.0.0.1:8080/signal/send_peer"

msg_text="🚀 Новая сборка Savun готова! Дата: ${build_date} · ${size}"
payload="m0e-chat-v1:{\"type\":\"file\",\"from\":\"server-relay\",\"text\":\"${msg_text}\",\"senderNickname\":\"Savun Pipeline\",\"download_url\":\"${download_link}\",\"attachment_name\":\"savun-fixed.apk\",\"attachment_size\":${bytes},\"attachment_mime\":\"application/vnd.android.package-archive\",\"ts\":${ts}}"
escaped_payload="${payload//\"/\\\"}"

curl -s -X POST "$LUCY_SEND_URL" \
    -H "Content-Type: application/json" \
    -d "{\"to_peer_id\": \"${LUCY_PEER_ID}\", \"from_peer_id\": \"server-relay\", \"payload\": \"${escaped_payload}\"}"
