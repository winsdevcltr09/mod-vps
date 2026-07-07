#!/bin/bash
NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"
SSH_PORT=2222
TUNNEL_LOG="/tmp/tunnel.log"

echo "============================================="
echo "  mod-vps starting ($(date -u))"
echo "  tunnel: pinggy.io:443 (TCP)"
echo "  ntfy  : ntfy.sh/$NTFY_TOPIC"
echo "============================================="

echo "root:${BOT_PASSWORD}" | chpasswd

sed -i "/^Port /d" /etc/ssh/sshd_config
echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
mkdir -p /run/sshd && ssh-keygen -A 2>/dev/null

echo "[1/4] Starting sshd on port $SSH_PORT..."
/usr/sbin/sshd && echo "      sshd OK"

echo "[2/4] Connecting pinggy.io tunnel via port 443..."
rm -f "$TUNNEL_LOG"
# pinggy.io: free TCP tunnel via SSH on port 443
# Output: tcp://TOKEN.a.pinggy.io:PORT or similar
ssh -p 443 \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=no \
    -o LogLevel=VERBOSE \
    -R "0:localhost:$SSH_PORT" \
    a.pinggy.io > "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

TUNNEL_ADDR=""
for i in $(seq 1 30); do
  sleep 2
  RAW=$(cat "$TUNNEL_LOG" 2>/dev/null)
  # Pinggy output: "tcp://HOST:PORT" or "Forwarding tcp connections from HOST:PORT"
  TUNNEL_ADDR=$(echo "$RAW" | grep -oP "tcp://\S+:\d+|(?<=from )\S+:\d+" | head -1)
  LAST=$(echo "$RAW" | grep -v "^$" | tail -1)
  echo "      [${i}x2s] ${LAST:0:80}"
  if [ -n "$TUNNEL_ADDR" ]; then break; fi
  if ! kill -0 $TUNNEL_PID 2>/dev/null; then
    echo "      pinggy died, restarting..."
    ssh -p 443 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 \
        -o LogLevel=VERBOSE \
        -R "0:localhost:$SSH_PORT" a.pinggy.io >> "$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!
  fi
done

echo "[3/4] Sending ntfy notification..."
if [ -n "$TUNNEL_ADDR" ]; then
  # Extract host:port from tcp://host:port
  CONN=$(echo "$TUNNEL_ADDR" | sed 's|tcp://||')
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@${CONN%:*} -p ${CONN##*:}
Password: ${BOT_PASSWORD}

Waktu: $(date -u '+%H:%M UTC')"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1
  echo "      Notifikasi terkirim ✓"
  echo "============================================="
  echo "  $TUNNEL_ADDR"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  echo "      Tunnel timeout! Log:"
  cat "$TUNNEL_LOG" | tail -20
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Tunnel Gagal" \
    -H "Priority: urgent" -H "Tags: warning" \
    -d "pinggy gagal. Log: $(cat $TUNNEL_LOG | tail -8 | tr '\n' ' ')" > /dev/null 2>&1
fi

# HTTP health check (required by Render)
python3 -c "
import http.server,os
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        b=b'OK - mod-vps running'
        self.send_response(200);self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def log_message(self,f,*a):pass
http.server.HTTPServer(('0.0.0.0',int(os.environ.get('PORT',8080))),H).serve_forever()
"
