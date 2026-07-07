#!/bin/bash
NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"
SSH_PORT=2222
BORE_LOG="/tmp/bore.log"
# bore.pub IP hardcoded (bypass DNS - Render Singapore cannot resolve bore.pub)
BORE_SERVER="159.223.110.159"
BORE_PORT=3977

echo "============================================="
echo "  mod-vps starting ($(date -u))"
echo "  tunnel: bore.pub ($BORE_SERVER:$BORE_PORT)"
echo "  ntfy  : ntfy.sh/$NTFY_TOPIC"
echo "============================================="

echo "root:${BOT_PASSWORD}" | chpasswd

sed -i "/^Port /d" /etc/ssh/sshd_config
echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
mkdir -p /run/sshd && ssh-keygen -A 2>/dev/null

echo "[1/4] Starting sshd on port $SSH_PORT..."
/usr/sbin/sshd && echo "      sshd OK"

echo "[2/4] Downloading bore v0.6.0..."
wget -q -O /tmp/bore.tar.gz "https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-v0.6.0-x86_64-unknown-linux-musl.tar.gz" \
  && tar -xz -C /usr/local/bin -f /tmp/bore.tar.gz \
  && chmod +x /usr/local/bin/bore \
  && echo "      bore $(bore --version 2>&1)"

echo "[3/4] Starting bore tunnel: localhost:$SSH_PORT -> $BORE_SERVER:$BORE_PORT..."
rm -f "$BORE_LOG"
# Use IP directly (musl libc bore binary may not read /etc/hosts)
bore local $SSH_PORT --to $BORE_SERVER:$BORE_PORT > "$BORE_LOG" 2>&1 &
BORE_PID=$!

BORE_ADDR=""
for i in $(seq 1 30); do
  sleep 2
  RAW=$(cat "$BORE_LOG" 2>/dev/null)
  # bore output: "listening at bore.pub:PORT"
  BORE_ADDR=$(echo "$RAW" | grep -oP "listening at \K\S+:\d+")
  LAST=$(echo "$RAW" | grep -v "^$" | tail -1)
  echo "      [${i}x2s] ${LAST:0:80}"
  if [ -n "$BORE_ADDR" ]; then break; fi
  if ! kill -0 $BORE_PID 2>/dev/null; then
    echo "      bore died, restart..."
    bore local $SSH_PORT --to $BORE_SERVER:$BORE_PORT >> "$BORE_LOG" 2>&1 &
    BORE_PID=$!
  fi
done

echo "[4/4] Sending ntfy notification..."
if [ -n "$BORE_ADDR" ]; then
  BORE_REMOTE_PORT=$(echo "$BORE_ADDR" | grep -oP "\d+$")
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@bore.pub -p ${BORE_REMOTE_PORT}
Password: ${BOT_PASSWORD}

Waktu: $(date -u '+%H:%M UTC')"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1
  echo "      Notifikasi terkirim ✓"
  echo "============================================="
  echo "  ssh root@bore.pub -p ${BORE_REMOTE_PORT}"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  echo "      Bore timeout! Full log:"
  cat "$BORE_LOG"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Bore Gagal" \
    -H "Priority: urgent" -H "Tags: warning" \
    -d "Bore gagal (IP=$BORE_SERVER). Log: $(cat $BORE_LOG | tail -5 | tr '\n' ' ')" > /dev/null 2>&1
fi

# HTTP health check (required by Render - must respond on $PORT)
python3 -c "
import http.server,os
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b=b'OK - mod-vps running'
        self.send_response(200);self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def log_message(self,f,*a):pass
http.server.HTTPServer(('0.0.0.0',int(os.environ.get('PORT',8080))),H).serve_forever()
"
