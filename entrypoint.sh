#!/bin/bash
NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"
SSH_PORT=2222
TUNNEL_LOG="/tmp/tunnel.log"

echo "============================================="
echo "  mod-vps starting ($(date -u))"
echo "  tunnel: pinggy.io TCP via port 443"
echo "  ntfy  : ntfy.sh/$NTFY_TOPIC"
echo "============================================="

echo "root:${BOT_PASSWORD}" | chpasswd

sed -i "/^Port /d" /etc/ssh/sshd_config
echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
mkdir -p /run/sshd && ssh-keygen -A 2>/dev/null

echo "[1/4] Starting sshd on port $SSH_PORT..."
/usr/sbin/sshd && echo "      sshd OK"

echo "[2/4] Connecting pinggy.io TCP tunnel via port 443..."
rm -f "$TUNNEL_LOG"
# tcp@a.pinggy.io = TCP tunnel mode; port 443 bypasses firewall
ssh -p 443 \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=no \
    -R "0:localhost:$SSH_PORT" \
    tcp@a.pinggy.io > "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

TUNNEL_ADDR=""
for i in $(seq 1 35); do
  sleep 2
  RAW=$(cat "$TUNNEL_LOG" 2>/dev/null)
  # Pinggy TCP output: "tcp://HOST:PORT"
  TUNNEL_ADDR=$(echo "$RAW" | grep -oP "tcp://\S+" | head -1)
  LAST=$(echo "$RAW" | grep -v "^$" | tail -1)
  echo "      [${i}x2s] ${LAST:0:80}"
  if [ -n "$TUNNEL_ADDR" ]; then break; fi
  if ! kill -0 $TUNNEL_PID 2>/dev/null; then
    echo "      pinggy died, restarting..."
    ssh -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 \
        -R "0:localhost:$SSH_PORT" tcp@a.pinggy.io >> "$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!
  fi
done

echo "[3/4] Sending ntfy notification..."
if [ -n "$TUNNEL_ADDR" ]; then
  # tcp://HOST:PORT -> extract host and port
  CONN="${TUNNEL_ADDR#tcp://}"
  THOST="${CONN%:*}"
  TPORT="${CONN##*:}"
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@${THOST} -p ${TPORT}
Password: ${BOT_PASSWORD}

Waktu: $(date -u '+%H:%M UTC')"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1
  echo "      Notifikasi terkirim ✓"
  echo "============================================="
  echo "  ssh root@${THOST} -p ${TPORT}"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  LOGSNIP=$(cat "$TUNNEL_LOG" 2>/dev/null | tail -8 | tr '\n' ' ')
  echo "      Tunnel timeout! Log: $LOGSNIP"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Tunnel Gagal" \
    -H "Priority: urgent" -H "Tags: warning" \
    -d "pinggy TCP gagal. Log: $LOGSNIP" > /dev/null 2>&1
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
