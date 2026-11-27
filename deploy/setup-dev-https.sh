#!/bin/sh
set -eu
dnf install -y nginx >/dev/null
mkdir -p /var/www/erp-acme/.well-known/acme-challenge
cat > /etc/nginx/conf.d/erp-http.conf <<'EOF'
server {
    listen 80;
    server_name 3.35.239.80;
    location ^~ /.well-known/acme-challenge/ { root /var/www/erp-acme; }
    location / { return 308 https://3.35.239.80$request_uri; }
}
EOF
nginx -t
systemctl enable --now nginx
systemctl reload nginx
docker pull certbot/certbot:v5.4.0 >/dev/null
cat > /usr/local/sbin/erp-certbot <<'EOF'
#!/bin/sh
set -eu
exec docker run --rm -v /etc/letsencrypt:/etc/letsencrypt -v /var/lib/letsencrypt:/var/lib/letsencrypt -v /var/www/erp-acme:/var/www/erp-acme certbot/certbot:v5.4.0 "$@"
EOF
chmod 755 /usr/local/sbin/erp-certbot
/usr/local/sbin/erp-certbot certonly --keep-until-expiring --non-interactive --agree-tos --register-unsafely-without-email --preferred-profile shortlived --webroot -w /var/www/erp-acme --ip-address 3.35.239.80
cat >/etc/nginx/conf.d/erp-https.conf <<'EOF'
server {
    listen 443 ssl;
    server_name 3.35.239.80;
    ssl_certificate /etc/letsencrypt/live/3.35.239.80/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/3.35.239.80/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location ~ ^/(api|health)/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header Forwarded "";
    }
    location / { return 404; }
}
EOF
cat >/etc/systemd/system/erp-cert-renew.service <<'EOF'
[Unit]
Description=Renew development API certificate
After=network-online.target docker.service nginx.service
Requires=docker.service nginx.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/erp-certbot renew --quiet --no-random-sleep-on-renew
ExecStartPost=/usr/bin/systemctl reload nginx
EOF
cat >/etc/systemd/system/erp-cert-renew.timer <<'EOF'
[Unit]
Description=Check development HTTPS certificate after boot and twice daily
[Timer]
OnBootSec=45s
OnCalendar=*-*-* 00,12:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
nginx -t
systemctl reload nginx
systemctl daemon-reload
systemctl enable --now erp-cert-renew.timer
