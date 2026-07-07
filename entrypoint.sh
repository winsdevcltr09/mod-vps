#!/bin/bash
NTFY_TOPIC="${NTFY_TOPIC:-render-vps}"
BOT_PASSWORD="${BOT_PASSWORD:-rairukun2025}"
HTTP_PORT="${PORT:-8080}"
SSH_PORT=2222
TUNNEL_LOG="/tmp/serveo.log"

echo "============================================="
echo "  mod-vps starting ($(date -u))"
echo "  tunnel: serveo.net"
echo "  ntfy  : ntfy.sh/$NTFY_TOPIC"
echo "  http  : $HTTP_PORT"
echo "============================================="

# Set root password
echo "root:${BOT_PASSWORD}" | chpasswd

# SSH config on port 2222
sed -i "/^Port /d" /etc/ssh/sshd_config
echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
mkdir -p /run/sshd
ssh-keygen -A 2>/dev/null

# Start SSH
echo "[1/4] Starting sshd on port $SSH_PORT..."
/usr/sbin/sshd
sleep 1 && ss -tlnp | grep "$SSH_PORT" && echo "      sshd OK" || echo "      sshd check done"

# Generate key for serveo tunnel
ssh-keygen -t ed25519 -f /tmp/serveo_key -N "" -q 2>/dev/null

# Start serveo.net reverse SSH tunnel
echo "[2/4] Starting serveo.net tunnel (localhost:$SSH_PORT -> serveo.net)..."
rm -f "$TUNNEL_LOG"
ssh -i /tmp/serveo_key \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes \
    -R "0:localhost:$SSH_PORT" \
    serveo.net > "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

# Wait up to 60s for serveo to give us a port
SERVEO_PORT=""
for i in $(seq 1 30); do
  sleep 2
  # serveo output: "Forwarding SSH connections from serveo.net" or port info
  RAW=$(cat "$TUNNEL_LOG" 2>/dev/null)
  SERVEO_PORT=$(echo "$RAW" | grep -oP "(?<=serveo\.net:)\d+|(?<=port )\d+" | head -1)
  echo "      [wait ${i}x2s] log: $(echo "$RAW" | tail -1 | cut -c1-80)"
  if [ -n "$SERVEO_PORT" ]; then break; fi
  # Restart if died
  if ! kill -0 $TUNNEL_PID 2>/dev/null; then
    echo "      serveo died, restarting..."
    ssh -i /tmp/serveo_key \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -R "0:localhost:$SSH_PORT" \
        serveo.net >> "$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!
  fi
done

# Send notification
echo "[3/4] Sending ntfy notification..."
if [ -n "$SERVEO_PORT" ]; then
  MSG="SSH VPS Render AKTIF!

Perintah koneksi:
ssh root@serveo.net -p ${SERVEO_PORT}
Password: ${BOT_PASSWORD}

Waktu: $(date -u '+%H:%M UTC')"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render Aktif" \
    -H "Priority: high" \
    -H "Tags: computer,key" \
    -d "$MSG" > /dev/null 2>&1
  echo "      Notifikasi terkirim ✓"
  echo "============================================="
  echo "  ssh root@serveo.net -p ${SERVEO_PORT}"
  echo "  Password: ${BOT_PASSWORD}"
  echo "============================================="
else
  echo "      Serveo timeout! Full log:"
  cat "$TUNNEL_LOG"
  curl -s -X POST "https://ntfy.sh/${NTFY_TOPIC}" \
    -H "Title: SSH VPS Render - Tunnel Gagal" \
    -H "Priority: urgent" \
    -H "Tags: warning" \
    -d "Tunnel gagal. Log: $(cat $TUNNEL_LOG | tail -5 | tr '\n' ' ')" > /dev/null 2>&1
fi

# HTTP health check server (wajib untuk Render)
echo "[4/4] Starting HTTP health server on :$HTTP_PORT..."
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
