#!/bin/bash
# ============================================================
# mod-vps FIXED Entrypoint
# - SSH via Bore tunnel
# - ntfy.sh notification when tunnel is up
# - Minimal HTTP server on $PORT for Render health check
# ============================================================

set -uo pipefail

NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
BORE_PORT="${BORE_PORT:-3977}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"

LOG_FILE="/var/log/bore-tunnel.log"

echo "============================================="
echo "  mod-vps starting..."
echo "  Bore server: $BORE_SERVER:$BORE_PORT"
echo "  ntfy topic : $NTFY_TOPIC"
echo "  HTTP port  : $HTTP_PORT"
echo "============================================="

# Set root password
echo "root:${BOT_PASSWORD}" | chpasswd

# Generate SSH host keys if missing
ssh-keygen -A 2>/dev/null

# Create required dirs
mkdir -p /run/sshd /var/log/supervisor /var/log/bots

# ---------- Start SSH ----------
echo "[1/4] Starting SSH server..."
/usr/sbin/sshd
echo "      SSH running on port 22 ✓"

# ---------- Start Bore tunnel ----------
echo "[2/4] Starting Bore tunnel (22 -> $BORE_SERVER:$BORE_PORT)..."
# FIXED: correct syntax is: bore local PORT --to SERVER:PORT
bore local 22 --to "${BORE_SERVER}:${BORE_PORT}" 2>&1 | tee "$LOG_FILE" &
BORE_PID=$!

# Wait for bore to establish connection (parse output)
BORE_URL=""
for i in $(seq 1 30); do
  sleep 1
  # Bore output: "listening at bore.pub:PORT"
  BORE_URL=$(grep -oP "(?<=listening at )[\w.]+:\d+" "$LOG_FILE" 2>/dev/null | head -1)
  if [ -n "$BORE_URL" ]; then
    break
  fi
done

echo "      Bore tunnel: $BORE_URL"

# ---------- Send ntfy notification ----------
echo "[3/4] Sending ntfy notification..."
if [ -n "$BORE_URL" ]; then
  BORE_HOST=$(echo "$BORE_URL" | cut -d: -f1)
  BORE_CONN_PORT=$(echo "$BORE_URL" | cut -d: -f2)
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@${BORE_HOST} -p ${BORE_CONN_PORT}
Password: ${BOT_PASSWORD}

Waktu: $(date '+%H:%M %Z')"

  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" \
    -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1

  echo "      Notifikasi terkirim ke ntfy.sh/$NTFY_TOPIC ✓"
  echo ""
  echo "============================================="
  echo "  SSH VPS AKTIF:"
  echo "  ssh root@${BORE_HOST} -p ${BORE_CONN_PORT}"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  echo "      WARN: Bore belum konek, kirim notif error..."
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Bore Timeout" \
    -H "Priority: urgent" \
    -H "Tags: warning" \
    -d "Bore tunnel timeout. Cek log Render." > /dev/null 2>&1
fi

# ---------- Start HTTP health check server (Render requirement) ----------
echo "[4/4] Starting HTTP health server on port $HTTP_PORT..."
python3 -c "
import http.server, os, threading

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'OK - mod-vps running'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, fmt, *args):
        pass  # suppress access logs

port = int(os.environ.get('PORT', 8080))
server = http.server.HTTPServer(('0.0.0.0', port), Handler)
print(f'Health server: 0.0.0.0:{port}')
server.serve_forever()
"