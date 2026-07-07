#!/bin/bash
NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
BORE_PORT="${BORE_PORT:-3977}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"
LOG_FILE="/tmp/bore-tunnel.log"

echo "============================================="
echo "  mod-vps starting..."
echo "  Bore: $BORE_SERVER:$BORE_PORT"
echo "  ntfy: $NTFY_TOPIC"
echo "  HTTP: $HTTP_PORT"
echo "============================================="

echo "root:${BOT_PASSWORD}" | chpasswd
ssh-keygen -A 2>/dev/null
mkdir -p /run/sshd /tmp

echo "[1/4] Starting SSH server..."
/usr/sbin/sshd && echo "      SSH OK"

echo "[2/4] Starting Bore tunnel (22 -> $BORE_SERVER:$BORE_PORT)..."
# bore v0.6.0 syntax: bore local PORT --to SERVER:PORT
bore local 22 --to "${BORE_SERVER}:${BORE_PORT}" > "$LOG_FILE" 2>&1 &
BORE_PID=$!

BORE_CONN_PORT=""
for i in $(seq 1 30); do
  sleep 2
  # bore v0.6.0 output: "listening at bore.pub:PORT"
  BORE_CONN_PORT=$(grep -oP "(?<=listening at )[\w.-]+:\K\d+" "$LOG_FILE" 2>/dev/null | head -1)
  if [ -n "$BORE_CONN_PORT" ]; then break; fi
done

echo "[3/4] Sending ntfy notification..."
if [ -n "$BORE_CONN_PORT" ]; then
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@${BORE_SERVER} -p ${BORE_CONN_PORT}
Password: ${BOT_PASSWORD}

Waktu: $(date '+%H:%M %Z')"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" \
    -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1
  echo "      Notifikasi terkirim -> ntfy.sh/$NTFY_TOPIC"
  echo "============================================="
  echo "  ssh root@${BORE_SERVER} -p ${BORE_CONN_PORT}"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  echo "      WARN: Bore timeout, kirim notif error..."
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Bore Timeout" \
    -H "Priority: urgent" \
    -H "Tags: warning" \
    -d "Bore tunnel gagal konek. Cek log Render." > /dev/null 2>&1
fi

echo "[4/4] Starting HTTP health server on :$HTTP_PORT..."
python3 -c "
import http.server, os, subprocess

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'OK - mod-vps running'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args): pass

port = int(os.environ.get('PORT', 8080))
print(f'Health server: 0.0.0.0:{port}')
http.server.HTTPServer(('0.0.0.0', port), Handler).serve_forever()
"