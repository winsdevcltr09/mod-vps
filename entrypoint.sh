#!/bin/bash
NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BORE_SERVER="${BORE_SERVER:-bore.pub}"
BORE_PORT="${BORE_PORT:-3977}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"
LOG_FILE="/tmp/bore.log"
SSH_PORT=2222

echo "============================================="
echo "  mod-vps starting ($(date -u))"
echo "  bore: $BORE_SERVER:$BORE_PORT"
echo "  ntfy: ntfy.sh/$NTFY_TOPIC"
echo "  http: $HTTP_PORT"
echo "============================================="

# Set password
echo "root:${BOT_PASSWORD}" | chpasswd 2>&1

# SSH config: use port 2222 (safer in containers)
sed -i "s/#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config || echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
mkdir -p /run/sshd
ssh-keygen -A 2>/dev/null

# Start SSH on port 2222
echo "[1/4] Starting sshd on port $SSH_PORT..."
/usr/sbin/sshd -p $SSH_PORT -D &
SSHD_PID=$!
sleep 2
if kill -0 $SSHD_PID 2>/dev/null; then
  echo "      sshd OK (pid $SSHD_PID)"
else
  echo "      sshd FAILED - trying default config..."
  /usr/sbin/sshd -D &
fi

# Start bore tunnel
echo "[2/4] Starting bore local $SSH_PORT --to $BORE_SERVER:$BORE_PORT ..."
rm -f "$LOG_FILE"
bore local $SSH_PORT --to "${BORE_SERVER}:${BORE_PORT}" > "$LOG_FILE" 2>&1 &
BORE_PID=$!

# Wait up to 60s for bore to connect
BORE_RESULT=""
for i in $(seq 1 30); do
  sleep 2
  echo "      [bore wait $((i*2))s] $(cat $LOG_FILE 2>/dev/null | tail -2 | tr '\n' ' ')"
  # bore v0.6.0: "listening at bore.pub:PORT"
  BORE_RESULT=$(grep -oP "(?<=listening at )\S+:\d+" "$LOG_FILE" 2>/dev/null | head -1)
  if [ -n "$BORE_RESULT" ]; then break; fi
  # Check if bore died
  if ! kill -0 $BORE_PID 2>/dev/null; then
    echo "      bore process died! Restarting..."
    bore local $SSH_PORT --to "${BORE_SERVER}:${BORE_PORT}" >> "$LOG_FILE" 2>&1 &
    BORE_PID=$!
  fi
done

# Send ntfy notification
echo "[3/4] Sending ntfy notification..."
if [ -n "$BORE_RESULT" ]; then
  BORE_HOST=$(echo "$BORE_RESULT" | cut -d: -f1)
  BORE_CONN_PORT=$(echo "$BORE_RESULT" | cut -d: -f2)
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@${BORE_HOST} -p ${BORE_CONN_PORT}
Password: ${BOT_PASSWORD}

Port SSH internal: $SSH_PORT
Waktu: $(date -u '+%H:%M UTC')"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" \
    -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1
  echo "      Notifikasi terkirim ✓"
  echo "============================================="
  echo "  ssh root@${BORE_HOST} -p ${BORE_CONN_PORT}"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  echo "      Bore timeout setelah 60s."
  echo "      Bore log akhir:"
  cat "$LOG_FILE" | tail -10
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Bore Gagal" \
    -H "Priority: urgent" \
    -H "Tags: warning" \
    -d "Bore tunnel gagal. Log: $(cat $LOG_FILE | tail -3 | tr '\n' ' ')" > /dev/null 2>&1
fi

# HTTP health check server (Render requirement)
echo "[4/4] Starting HTTP server on :$HTTP_PORT..."
python3 -c "
import http.server, os

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b=b'OK - mod-vps running'
        self.send_response(200)
        self.send_header('Content-Length',str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def log_message(self,f,*a):pass

http.server.HTTPServer(('0.0.0.0',int(os.environ.get('PORT',8080))),H).serve_forever()
"