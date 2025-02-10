#!/bin/bash

# Variables
HAPROXY_CFG_PATH="/etc/haproxy/haproxy.cfg"
BACKUP_CFG_PATH="/etc/haproxy/haproxy.cfg.bak"

# SEBASTIAN
DUCKDNS_DOMAIN="srestrepoj-wordpress.duckdns.org"  # CAMBIAR POR DOMINIO DE WORDPRESS
DUCKDNS_TOKEN="d9c2144c-529b-4781-80b7-20ff1a7595de" # PONER TOKEN DE CUENTA

SSL_PATH="/etc/letsencrypt/live/$DUCKDNS_DOMAIN"
CERT_PATH="$SSL_PATH/fullchain.pem"
LOG_FILE="/var/log/script.log"

# Redirigir toda la salida a LOG_FILE
exec > >(tee -a $LOG_FILE) 2>&1

# CONFIGURACION DUCKDNS
mkdir -p /home/ubuntu/duckdns

cat <<EOL > /home/ubuntu/duckdns/duck.sh
echo url="https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" | curl -k -o /dev/null -K -
EOL

chmod +x /home/ubuntu/duckdns/duck.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/ubuntu/duckdns/duck.sh >/dev/null 2>&1") | crontab -

# INSTALACION DE CERTBOT
sudo apt-get install -y certbot

# CONFIGURACION DE LET'S ENCRYPT (Certbot)
if [ -f "$CERT_PATH" ]; then
    sudo certbot renew --non-interactive --quiet
else
    sudo certbot certonly --standalone -d $DUCKDNS_DOMAIN --non-interactive --agree-tos -m admin@$DUCKDNS_DOMAIN
fi

# FUSIONAR ARCHIVOS DE CERTIFICADO
sudo cat /etc/letsencrypt/live/$DUCKDNS_DOMAIN/fullchain.pem \
/etc/letsencrypt/live/$DUCKDNS_DOMAIN/privkey.pem \
| sudo tee /etc/letsencrypt/live/$DUCKDNS_DOMAIN/haproxy.pem

# DAR PERMISOS AL CERTIFICADO
sudo chmod 644 /etc/letsencrypt/live/$DUCKDNS_DOMAIN/haproxy.pem
sudo chmod 755 -R /etc/letsencrypt/live/$DUCKDNS_DOMAIN
sudo chmod 755 /etc/letsencrypt/live/

# INSTALACION DE HAPROXY
sudo apt-get update
sudo apt-get install -y haproxy

# HACER COPIA DE SEGURIDAD DE LA CONFIGURACION INICIAL
sudo cp "$HAPROXY_CFG_PATH" "$BACKUP_CFG_PATH"

# CONFIGURAR HAPROXY
sudo tee "$HAPROXY_CFG_PATH" > /dev/null <<EOL
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend wordpress_front
    bind *:80
    bind *:443 ssl crt /etc/letsencrypt/live/$DUCKDNS_DOMAIN/haproxy.pem
    mode http
    redirect scheme https if !{ ssl_fc }
    default_backend wordpress_back

backend wordpress_back
    mode http
    balance roundrobin
    server wordpress1 10.225.4.10:80 check
EOL

# REINICIAR Y HABILITAR HAPROXY
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# VERIFICAR ESTADO DE HAPROXY
sudo systemctl status haproxy --no-pager

 ################
#  Copiar A wordpress, para configurarlo  
# sudo scp -i "ssh-mensagl-2025-sebastian.pem" -r /etc/letsencrypt/live/srestrepoj-wordpress.duckdns.orgubuntu@10.225.4.10:/home/ubuntu             #
 ################