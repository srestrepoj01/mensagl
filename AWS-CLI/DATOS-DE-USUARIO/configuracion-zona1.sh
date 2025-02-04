#!/bin/bash
apt-get update -y
apt-get install haproxy -y

cat <<CONFIG > /etc/haproxy/haproxy.cfg
frontend http_front
    bind *:80
    default_backend http_back

backend http_back
    server backend1 10.225.3.20:80 check
    server backend2 10.225.3.30:80 check
CONFIG

systemctl restart haproxy
systemctl enable haproxy

mkdir -p /opt/duckdns
cd /opt/duckdns

cat <<DUCKDNS_SCRIPT > duckdns.sh
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o /opt/duckdns/duck.log -K -
DUCKDNS_SCRIPT
chmod +x duckdns.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/duckdns/duckdns.sh >/dev/null 2>&1") | crontab -
echo "DDNS INSTALADO / CONFIGURADO"
Theme Switch

