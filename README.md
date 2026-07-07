# mod-vps (Fixed)

SSH VPS via Bore tunnel — dapat di-deploy ke Render/Railway secara gratis.
Fork dari [devculture67/mod-vps](https://github.com/devculture67/mod-vps) dengan perbaikan bug.

## Bug yang diperbaiki
- Syntax bore diperbaiki (`bore local PORT --to SERVER:PORT`)
- Quote ekstra di `chpasswd` dihapus
- Render health check HTTP server ditambahkan
- ntfy.sh notifikasi otomatis saat VPS aktif
- `render.yaml` diperbaiki ke repo yang benar
- Prometheus/Grafana dihapus (terlalu berat untuk Render free)

## Deploy ke Render
1. Fork repo ini ke akun GitHub kamu
2. Connect ke Render → New Web Service → Docker
3. Set env vars: `BOT_PASSWORD`, `BORE_SERVER`, `BORE_PORT`
4. Deploy!

## Notifikasi
Buka app ntfy → subscribe topic `render-vps`
Setiap VPS start, kamu dapat notif SSH connection info.

## Koneksi SSH
Lihat notifikasi ntfy atau Render logs:
```
ssh root@bore.pub -p PORT
Password: (isi BOT_PASSWORD)
```
