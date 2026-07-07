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

RUN apt-get update && apt-get install -y \
    openssh-server curl wget tar python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Download bore binary dari release yang benar (x86_64 linux musl tar.gz)
RUN wget -q https://github.com/ekzhang/bore/releases/download/v0.6.0/bore-v0.6.0-x86_64-unknown-linux-musl.tar.gz \
    -O /tmp/bore.tar.gz \
    && tar -xzf /tmp/bore.tar.gz -C /tmp \
    && mv /tmp/bore /usr/local/bin/bore \
    && chmod +x /usr/local/bin/bore \
    && rm /tmp/bore.tar.gz

# Setup SSH
RUN mkdir -p /run/sshd \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config \
    && echo 'UseDNS no' >> /etc/ssh/sshd_config \
    && ssh-keygen -A

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
CMD ["/entrypoint.sh"]