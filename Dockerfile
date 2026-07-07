FROM debian:bullseye-slim

ARG BORE_SERVER=bore.pub
ARG BORE_PORT=3977
ARG BOT_PASSWORD=rairukun2025
ARG NTFY_TOPIC=render-vps

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Jakarta
ENV BOT_PASSWORD=${BOT_PASSWORD}
ENV NTFY_TOPIC=${NTFY_TOPIC}

RUN apt-get update && apt-get install -y \
    openssh-server openssh-client \
    curl wget tar python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Setup SSH server
RUN mkdir -p /run/sshd \
    && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "UseDNS no" >> /etc/ssh/sshd_config \
    && ssh-keygen -A

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
CMD ["/entrypoint.sh"]
