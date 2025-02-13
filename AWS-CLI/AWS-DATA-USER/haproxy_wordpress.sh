#!/bin/bash

# Variables
HAPROXY_CFG_PATH="/etc/haproxy/haproxy.cfg"
BACKUP_CFG_PATH="/etc/haproxy/haproxy.cfg.bak"
DUCKDNS_DOMAIN="srestrepoj-wordpress01"
DUCKDNS_TOKEN="d9c2144c-529b-4781-80b7-20ff1a7595de"
DUCKDNS_DOMAIN_CERT="srestrepoj-wordpress01.duckdns.org"
SSL_PATH="/etc/letsencrypt/live/${DUCKDNS_DOMAIN}"
CERT_PATH="${SSL_PATH}/fullchain.pem"
LOG_FILE="/var/log/script.log"

# Redirige toda la salida al archivo de registro LOG_FILE
exec > >(tee -a "${LOG_FILE}") 2>&1

# Configuración de DUCKDNS
mkdir -p /home/ubuntu/duckdns

# Crea el script de actualización de DuckDNS
cat <<EOL > /home/ubuntu/duckdns/duck.sh
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o /home/ubuntu/duckdns/duck.log -K -
EOL

# Cambia la propiedad y los permisos del script
cd /home/ubuntu/duckdns
chmod 700 duck.sh

# Agrega la tarea al crontab solo si no está presente
CRON_JOB="@reboot /home/ubuntu/duckdns/duck.sh >/dev/null 2>&1"
(crontab -l 2>/dev/null | grep -Fxq "$CRON_JOB") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

# Prueba el script
/home/ubuntu/duckdns/duck.sh

# Verifica el resultado del último intento
cat /home/ubuntu/duckdns/duck.log

# Instala Certbot
apt update && DEBIAN_FRONTEND=noninteractive apt install -y certbot

# Configuración de Let's Encrypt (Certbot)
if [ -f "${CERT_PATH}" ]; then
    # Renueva el certificado si ya existe
    certbot renew --non-interactive --quiet
else
    # Solicita un nuevo certificado
    certbot certonly --standalone -d "${DUCKDNS_DOMAIN_CERT}" --non-interactive --agree-tos --email srestrepoj01@educantabria.es
fi

# Combina los archivos de certificado para HAProxy
cat "${SSL_PATH}/fullchain.pem" "${SSL_PATH}/privkey.pem" > "${SSL_PATH}/haproxy.pem"

# Establece permisos para el certificado
chmod 644 "${SSL_PATH}/haproxy.pem"
chmod 755 -R "${SSL_PATH}"
chmod 755 /etc/letsencrypt/live/

# Instala HAProxy
apt-get update
apt-get install -y haproxy

# Crea una copia de seguridad de la configuración inicial de HAProxy
cp "${HAPROXY_CFG_PATH}" "${BACKUP_CFG_PATH}"

# Configura HAProxy
tee "${HAPROXY_CFG_PATH}" > /dev/null <<EOL
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend wordpress_front
    bind *:80
    bind *:443 ssl crt ${SSL_PATH}/haproxy.pem
    mode http
    redirect scheme https if !{ ssl_fc }
    default_backend wordpress_back

backend wordpress_back
    mode http
    balance source
    server wordpress1 10.225.4.10:80 check
    server wordpress2 10.225.4.11:80 check
EOL

# Reinicia y habilita HAProxy
systemctl restart haproxy
systemctl enable haproxy

# Verifica el estado de HAProxy
systemctl status haproxy --no-pager
