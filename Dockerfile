# ============================================================
# mod-vps FIXED — SSH Gateway via Bore tunnel
# Deployable on Render free tier
# Fixes: bore syntax, chpasswd quote, render health check
# ============================================================
FROM debian:bullseye-slim

ARG BORE_SERVER=bore.pub
ARG BORE_PORT=3977
ARG BOT_PASSWORD=rairukun2025
ARG NTFY_TOPIC=render-vps

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta
ENV BORE_SERVER=${BORE_SERVER}
ENV BORE_PORT=${BORE_PORT}
ENV BOT_PASSWORD=${BOT_PASSWORD}
ENV NTFY_TOPIC=${NTFY_TOPIC}

# ---------- BASE SYSTEM ----------
RUN apt-get update && apt-get install -y \
    openssh-server \
    curl wget \
    python3 \
    supervisor \
    openssl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------- BORE CLIENT (correct binary) ----------
RUN wget -q https://github.com/ekzhang/bore/releases/latest/download/bore-linux-amd64 \
    -O /usr/local/bin/bore \
    && chmod +x /usr/local/bin/bore

# ---------- SSH CONFIG ----------
RUN mkdir -p /run/sshd \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && echo 'UseDNS no' >> /etc/ssh/sshd_config \
    && ssh-keygen -A

# ---------- SUPERVISOR CONFIG ----------
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ---------- ENTRYPOINT ----------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Render needs HTTP on $PORT for health check
EXPOSE 8080

CMD ["/entrypoint.sh"]