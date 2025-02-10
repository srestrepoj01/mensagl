#!/bin/bash

# Variables
HAPROXY_CFG_PATH="/etc/haproxy/haproxy.cfg"
BACKUP_CFG_PATH="/etc/haproxy/haproxy.cfg.bak"

# SEBASTIAN
#DUCKDNS_DOMAIN="srestrepoj-wordpress.duckdns.org"  # CAMBIAR POR DOMINIO DE WORDPRESS
#DUCKDNS_TOKEN="d9c2144c-529b-4781-80b7-20ff1a7595de" # PONER TOKEN DE CUENTA

# DAVID
DUCKDNS_DOMAIN="worpressdavid.duckdns.org" # CAMBIAR POR DOMINIO DE PROSODY
DUCKDNS_TOKEN="c452df5a-e345-4ab1-bbb4-a4d7d9f75d80" # PONER TOKEN DE CUENTA

SSL_PATH="/etc/letsencrypt/live/$DUCKDNS_DOMAIN"
CERT_PATH="$SSL_PATH/fullchain.pem"

# CONFIGURACION DUCKDNS
echo "Instalando y configurando DuckDNS..."
mkdir -p /home/ubuntu/duckdns

cat <<EOL > /home/ubuntu/duckdns/duck.sh
echo url="https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" | curl -k -o /dev/null -K -
EOL

chmod +x /home/ubuntu/duckdns/duck.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/ubuntu/duckdns/duck.sh >/dev/null 2>&1") | crontab -

# INSTALACION DE CERTBOT
echo "Instalando Certbot..."
sudo apt-get install -y certbot

# CONFIGURACION DE LET'S ENCRYPT (Certbot)
echo "Verificando si el certificado SSL ya existe..."
if [ -f "$CERT_PATH" ]; then
    echo "Certificado encontrado. Intentando renovar..."
    sudo certbot renew --non-interactive --quiet
else
    echo "No se encontro un certificado existente. Instalando uno nuevo..."
    sudo certbot certonly --standalone -d $DUCKDNS_DOMAIN --non-interactive --agree-tos -m admin@$DUCKDNS_DOMAIN
fi

# INSTALACION DE HAPROXY
echo "Instalando HAProxy..."
sudo apt-get update
sudo apt-get install -y haproxy

# HACER COPIA DE SEGURIDAD DE LA CONFIGURACION INICIAL
echo "Realizando backup de la configuración actual..."
sudo cp "$HAPROXY_CFG_PATH" "$BACKUP_CFG_PATH"

# CONFIGURAR HAPROXY
echo "Aplicando nueva configuración de HAProxy..."
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
    bind *:443 ssl crt $SSL_PATH
    mode http
    default_backend wordpress_back

backend wordpress_back
    mode http
    balance roundrobin
    server wordpress1 10.225.4.10:80 check
EOL

# REINICIAR Y HABILITAR HAPROXY
echo "Reiniciando HAProxy..."
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# VERIFICAR ESTADO DE HAPROXY
echo "Estado de HAProxy:"
sudo systemctl status haproxy --no-pager