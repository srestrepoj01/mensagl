#!/bin/bash

# Variables
NOMBRE=" proxyzona2-equipo5" # NOMBRE CAMBIAR
TOKEN="81e7e3e8-ed00-4d63-b671-2f5207ca02f7" # TOKEN PRUEBA LUEGO CAMBIAR
EMAIL="retoequipo5@gmail.com"  # CORREO CAMBIAR 

# Actualizar DuckDNS
echo "Actualizando DuckDNS para $NOMBRE.duckdns.org"
curl "https://www.duckdns.org/update?domains=$NOMBRE&token=$TOKEN&ip="

# Configurar cron job para actualizar DuckDNS cada 5 minutos
(crontab -l ; echo "*/5 * * * * curl -s 'https://www.duckdns.org/update?domains=$NOMBRE&token=$TOKEN&ip='") | crontab -

# Instalar Certbot
sudo apt-get update
sudo apt-get install -y certbot

# Parar temporalmente HAProxy para liberar los puertos 80 y 443
sudo systemctl stop haproxy

# Solicitar certificado SSL
sudo certbot certonly --standalone -d "$NOMBRE.duckdns.org" --agree-tos --email "$EMAIL"

# Configurar renovación automática del certificado
(crontab -l ; echo "0 0 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl restart haproxy'") | crontab -

# Configurar HAProxy para el servicio de mensajería (Zona 2)
sudo tee /etc/haproxy/haproxy.cfg <<EOF
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

frontend http_front
    bind *:80
    default_backend http_back

backend http_back
    balance roundrobin
    server mensajeria2 10.0.4.10:80 check

frontend https_front
    bind *:443
    default_backend https_back

backend https_back
    balance roundrobin
    server mensajeria2 10.0.4.10:443 check
EOF

# AGREGAR LUEGO SEGUNDA IP CLUSTER
# server mensajeria2_1 10.0.3.30:443 check
# server mensajeria1_1 10.0.3.30:80 check

# Reiniciar HAProxy para aplicar la configuración
sudo systemctl start haproxy
