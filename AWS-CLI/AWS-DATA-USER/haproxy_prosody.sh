#!/bin/bash

# Variables
HAPROXY_CFG_PATH="/etc/haproxy/haproxy.cfg"
BACKUP_CFG_PATH="/etc/haproxy/haproxy.cfg.bak"
DUCKDNS_DOMAIN="srestrepoj-wp"
DUCKDNS_TOKEN="d9c2144c-529b-4781-80b7-20ff1a7595de"
SSL_PATH="/etc/letsencrypt/live/${DUCKDNS_DOMAIN}"
CERT_PATH="${SSL_PATH}/fullchain.pem"
DUCKDNS_DIR="/home/ubuntu/duckdns"
DUCKDNS_SCRIPT="${DUCKDNS_DIR}/duck.sh"
DUCKDNS_LOG="${DUCKDNS_DIR}/duck.log"
LOG_FILE="/var/log/script.log"
EMAIL="srestrepoj01@educantabria.es"

# Redirige la salida al archivo de registro
exec > >(sudo tee -a "${LOG_FILE}") 2>&1

# Configuración de DuckDNS
sudo mkdir -p "${DUCKDNS_DIR}"

# Crea el script de actualización de DuckDNS
sudo tee "${DUCKDNS_SCRIPT}" > /dev/null <<EOL
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o "${DUCKDNS_LOG}" -K -
EOL

# Cambia la propiedad y los permisos del script
sudo chown ubuntu:ubuntu "${DUCKDNS_SCRIPT}"
sudo chmod 700 "${DUCKDNS_SCRIPT}"

# Agrega la tarea al crontab para ejecutarse al reiniciar
CRON_JOB="@reboot ${DUCKDNS_SCRIPT} >/dev/null 2>&1"
(crontab -l 2>/dev/null; echo "${CRON_JOB}") | crontab -

# Prueba el script de actualización
sudo chmod +x "${DUCKDNS_SCRIPT}"
sudo "${DUCKDNS_SCRIPT}"

# Verifica el resultado del intento
sudo cat "${DUCKDNS_LOG}"

# Instala Certbot
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y certbot

# Configuración de Let's Encrypt
if [ -f "${CERT_PATH}" ]; then
    sudo certbot renew --non-interactive --quiet
else
    sudo certbot certonly --standalone -d "${DUCKDNS_DOMAIN}" --non-interactive --agree-tos --email "${EMAIL}"
fi

# Combina los archivos de certificado para HAProxy
sudo cat "${SSL_PATH}/fullchain.pem" "${SSL_PATH}/privkey.pem" | sudo tee "${SSL_PATH}/haproxy.pem" > /dev/null

# Establece permisos para el certificado
sudo chmod 644 "${SSL_PATH}/haproxy.pem"
sudo chmod 755 -R "${SSL_PATH}"
sudo chmod 755 /etc/letsencrypt/live/

# Instala HAProxy
sudo apt-get update
sudo apt-get install -y haproxy

# Crea una copia de seguridad de la configuración inicial de HAProxy
sudo cp "${HAPROXY_CFG_PATH}" "${BACKUP_CFG_PATH}"

# Configura HAProxy
sudo tee "${HAPROXY_CFG_PATH}" > /dev/null <<EOL
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
sudo systemctl restart haproxy
sudo systemctl enable haproxy

# Verifica el estado de HAProxy
sudo systemctl status haproxy --no-pager
