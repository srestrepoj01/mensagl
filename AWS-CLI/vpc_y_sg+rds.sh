#!/bin/bash

# ARCHIVO DE LOG
LOG_FILE="laboratorio.log"
# Redirigir toda la salida al archivo de log


###########################################                       
#            VARIABLES DE PRUEBA          #
###########################################

# Variables VPC
read -r -p "Pon el nombre del laboratorio: " NOMBRE_ALUMNO
REGION="us-east-1"
# Variables AMI-ID (Ubuntu server 24.04) y CLAVE SSH
KEY_NAME="ssh-mensagl-2025-${NOMBRE_ALUMNO}"
AMI_ID="ami-04b4f1a9cf54c11d0" # Llamar variable claves         

# Crear par de claves SSH y almacenar la clave en una variable
PEM_KEY=$(aws ec2 create-key-pair \
    --key-name "${KEY_NAME}" \
    --query "KeyMaterial" \
    --output text)

# Guardar la clave en un archivo
echo "${PEM_KEY}" > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"
echo "Clave SSH creada y almacenada en: ${KEY_NAME}.pem"

# Usar la variable PEM_KEY en otros comandos
echo "Contenido de la clave SSH almacenada en variable:"
echo "${PEM_KEY}"


# Variables para RDS, se pueden cambiar los valores por los deseados
RDS_INSTANCE_ID="wordpress-db"
read -r -p "Ingrese el nombre de la base de datos: " DB_NAME
read -r -p "Ingrese el nombre de usuario de la BD: " DB_USERNAME
read -r -p "Ingrese la contraseña de la BD: " DB_PASSWORD


exec > "$LOG_FILE" 2>&1

##############################                       
#             VPC            #
##############################

# Crear VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block "10.225.0.0/16" --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}"

# Crear Subnets publicas
SUBNET_PUBLIC1_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.225.1.0/24" --availability-zone "${REGION}a" --query 'Subnet.SubnetId' --output text)
SUBNET_PUBLIC2_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.225.2.0/24" --availability-zone "${REGION}b" --query 'Subnet.SubnetId' --output text)

# Crear Subnets privadas
SUBNET_PRIVATE1_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.225.3.0/24" --availability-zone "${REGION}a" --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE2_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.225.4.0/24" --availability-zone "${REGION}b" --query 'Subnet.SubnetId' --output text)

# Crear Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"

# Crear Tabla de Rutas Públicas
RTB_PUBLIC_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PUBLIC_ID" --destination-cidr-block "0.0.0.0/0" --gateway-id "$IGW_ID"
aws ec2 associate-route-table --subnet-id "$SUBNET_PUBLIC1_ID" --route-table-id "$RTB_PUBLIC_ID"
aws ec2 associate-route-table --subnet-id "$SUBNET_PUBLIC2_ID" --route-table-id "$RTB_PUBLIC_ID"

# Crear Elastic IP y NAT Gateway
EIP_ID=$(aws ec2 allocate-address --query 'AllocationId' --output text)
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$SUBNET_PUBLIC1_ID" --allocation-id "$EIP_ID" --query 'NatGateway.NatGatewayId' --output text)

echo "Creando GATEWAY NAT..."
while true; do
    STATUS=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$NAT_ID" --query 'NatGateways[0].State' --output text)
    echo "Estado del NAT Gateway: $STATUS"
    if [ "$STATUS" == "available" ]; then
        break
    fi
    sleep 10
done

# Crear Tabla de Rutas Privadas
RTB_PRIVATE1_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PRIVATE1_ID" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "$NAT_ID"
aws ec2 associate-route-table --subnet-id "$SUBNET_PRIVATE1_ID" --route-table-id "$RTB_PRIVATE1_ID"

RTB_PRIVATE2_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PRIVATE2_ID" --destination-cidr-block "0.0.0.0/0" --nat-gateway-id "$NAT_ID"
aws ec2 associate-route-table --subnet-id "$SUBNET_PRIVATE2_ID" --route-table-id "$RTB_PRIVATE2_ID"

##############################                       
# Crear Grupos de Seguridad  #
##############################

# Grupo de seguridad para los Proxy Inversos - Wordpress
SG_PROXY_WP_ID=$(aws ec2 create-security-group --group-name "sg_proxy_inverso-WP" --description "SG para el proxy inverso - wordpress" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_WP_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_WP_ID" --protocol tcp --port 443 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_WP_ID" --protocol tcp --port 80 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-egress --group-id "$SG_PROXY_WP_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

# Grupo de seguridad para los Proxy Inversos - Prosody
SG_PROXY_PROSODY_ID=$(aws ec2 create-security-group --group-name "sg_proxy_inverso-Prosody" --description "SG para el proxy inverso - prosody" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_PROSODY_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_PROSODY_ID" --protocol tcp --port 5222 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_PROSODY_ID" --protocol tcp --port 5269 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_PROSODY_ID" --protocol tcp --port 443 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_PROSODY_ID" --protocol tcp --port 80 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-egress --group-id  "$SG_PROXY_PROSODY_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

# Grupo de seguridad para el CMS
SG_CMS_ID=$(aws ec2 create-security-group --group-name "sg_cms" --description "SG para el cluster CMS" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_CMS_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_CMS_ID" --protocol tcp --port 80 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_CMS_ID" --protocol tcp --port 443 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_CMS_ID" --protocol tcp --port 33060 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_CMS_ID" --protocol tcp --port 53 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-egress --group-id "$SG_CMS_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

# Grupo de seguridad para MySQL
SG_MYSQL_ID=$(aws ec2 create-security-group --group-name "sg_mysql" --description "SG para servidores MySQL" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_MYSQL_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MYSQL_ID" --protocol tcp --port 3306 --source-group "$SG_MYSQL_ID"
aws ec2 authorize-security-group-ingress --group-id "$SG_MYSQL_ID" --protocol tcp --port 3306 --cidr "$(aws ec2 describe-subnets --subnet-ids "$SUBNET_PRIVATE1_ID" --query 'Subnets[0].CidrBlock' --output text)"
aws ec2 authorize-security-group-egress --group-id "$SG_MYSQL_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

# Grupo de seguridad para Mensajeria (XMPP Prosody + MySQL)
SG_MENSAJERIA_ID=$(aws ec2 create-security-group --group-name "sg_mensajeria" --description "SG para XMPP Prosody y MySQL" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 5222 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 5347 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 3306 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol udp --port 10000 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 5269 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 4443 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 5281 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 5280 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 80 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_MENSAJERIA_ID" --protocol tcp --port 443 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-egress --group-id "$SG_MENSAJERIA_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

##############################                       
#             RDS             #
##############################

# Crear subnet RD
aws rds create-db-subnet-group \
    --db-subnet-group-name wp-rds-subnet-group \
    --db-subnet-group-description "RDS Subnet Group for WordPress" \
    --subnet-ids "$SUBNET_PRIVATE1_ID" "$SUBNET_PRIVATE2_ID"


# SG de RDS
SG_ID_RDS=$(aws ec2 create-security-group \
  --group-name "RDS-MySQL" \
  --description "SG para RDS MySQL" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' \
  --output text)

# Permitir acceso MySQL
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID_RDS" \
  --protocol tcp \
  --port 3306 \
  --cidr 0.0.0.0/0  

# Crear instancia RDS (Single-AZ en Private Subnet 2)
aws rds create-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --db-instance-class db.t3.medium \
    --engine mysql \
    --allocated-storage 20 \
    --storage-type gp2 \
    --master-username "$DB_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --db-subnet-group-name wp-rds-subnet-group \
    --vpc-security-group-ids "$SG_ID_RDS" \
    --backup-retention-period 7 \
    --no-publicly-accessible \
    --availability-zone "us-east-1b" \
    --no-multi-az  # Se asegura que no se despliega en multiple AZ

# ESPERA A QUE EL RDS ESTE DISPONIBLE
echo "ESPERANDO A QUE EL RDS ESTE DISPONIBLE..."
aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE_ID"

# Recibe el RDS ENDPOINT PARA USARLO MAS ADELANTE
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)
echo "RDS Endpoint: $RDS_ENDPOINT"

##################################################                       
#             INSTANCIAS Y SERVICIOS             #
##################################################
# proxy-prosody
INSTANCE_NAME="proxy-prosody"
SUBNET_ID="${SUBNET_PUBLIC1_ID}"
SECURITY_GROUP_ID="${SG_PROXY_PROSODY_ID}"
PRIVATE_IP="10.225.1.10"
INSTANCE_TYPE="t2.micro"
VOLUME_SIZE=8

USER_DATA_SCRIPT=$(cat AWS-DATA-USER/haproxy_prosody.sh)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

# proxy-wordpress
INSTANCE_NAME="proxy-wordpress"
SUBNET_ID="${SUBNET_PUBLIC2_ID}"
PRIVATE_IP="10.225.2.10"
INSTANCE_TYPE="t2.micro"
SECURITY_GROUP_ID="${SG_PROXY_WP_ID}"
VOLUME_SIZE=8

USER_DATA_SCRIPT=$(cat <<EOF
#!/bin/bash

# Variables
HAPROXY_CFG_PATH="/etc/haproxy/haproxy.cfg"
BACKUP_CFG_PATH="/etc/haproxy/haproxy.cfg.bak"
DUCKDNS_DOMAIN="srestrepoj-wordpress.duckdns.org"  # CAMBIAR POR DOMINIO DE WORDPRESS
DUCKDNS_TOKEN="d9c2144c-529b-4781-80b7-20ff1a7595de" # PONER TOKEN DE CUENTA
SSL_PATH="/etc/letsencrypt/live/$DUCKDNS_DOMAIN"
CERT_PATH="$SSL_PATH/fullchain.pem"
LOG_FILE="/var/log/script.log"

# Redirigir toda la salida a LOG_FILE
exec > >(sudo tee -a $LOG_FILE) 2>&1

# CONFIGURACION DUCKDNS
sudo mkdir -p /home/ubuntu/duckdns

sudo cat <<EOL > /home/ubuntu/duckdns/duck.sh
echo url="https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=" | curl -k -o /home/ubuntu/duckdns/duck.log -K -
EOL

sudo chown ubuntu:ubuntu /home/ubuntu/duckdns/duck.sh
sudo chmod 700 /home/ubuntu/duckdns/duck.sh

# Agregar el cron job para ejecutar el script cada 5 minutos
(sudo crontab -l 2>/dev/null; echo "*/5 * * * * /home/ubuntu/duckdns/duck.sh >/dev/null 2>&1") | sudo crontab -

# Probar el script
sudo /home/ubuntu/duckdns/duck.sh

# Verificar el resultado del último intento
sudo cat /home/ubuntu/duckdns/duck.log

# INSTALACION DE CERTBOT
sudo apt update && sudo DEBIAN_FRONTEND=noninteractive apt install certbot -y

# CONFIGURACION DE LET'S ENCRYPT (Certbot)
if [ -f "$CERT_PATH" ]; then
    sudo certbot renew --non-interactive --quiet
else
    sudo certbot certonly --standalone -d $DUCKDNS_DOMAIN --non-interactive --agree-tos -m admin@$DUCKDNS_DOMAIN
fi

# FUSIONAR ARCHIVOS DE CERTIFICADO
sudo cat /etc/letsencrypt/live/$DUCKDNS_DOMAIN/fullchain.pem /etc/letsencrypt/live/$DUCKDNS_DOMAIN/privkey.pem | sudo tee /etc/letsencrypt/live/$DUCKDNS_DOMAIN/haproxy.pem > /dev/null

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

# Configurar la clave SSH
sudo mkdir -p /home/ubuntu/.ssh
sudo echo "${PEM_KEY}" > /home/ubuntu/.ssh/${KEY_NAME}.pem
sudo chmod 400 /home/ubuntu/.ssh/${KEY_NAME}.pem

# Copiar A wordpress, para configurarlo
sudo scp -i "/home/ubuntu/.ssh/${KEY_NAME}.pem" -r /etc/letsencrypt/live/$DUCKDNS_DOMAIN ubuntu@10.225.4.10:/home/ubuntu
EOF
)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data "$USER_DATA_SCRIPT" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

##############
#    MySQL   #
##############
# sgbd_principal
INSTANCE_NAME="sgbd_principal-zona1"
SUBNET_ID="${SUBNET_PRIVATE1_ID}"
SECURITY_GROUP_ID="${SG_MYSQL_ID}"
PRIVATE_IP="10.225.3.10"

# Cargar el script para la base de datos primaria
USER_DATA_SCRIPT=$(sed 's/role=".*"/role="primary"/' AWS-DATA-USER/configuracion-bd-primaria-y-slave.sh)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data "$USER_DATA_SCRIPT" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

# sgbd_secundario
INSTANCE_NAME="sgbd_replica-zona1"
PRIVATE_IP="10.225.3.11"

# Cargar el script para la base de datos secundaria
USER_DATA_SCRIPT=$(sed 's/role=".*"/role="secondary"/' AWS-DATA-USER/configuracion-bd-primaria-y-slave.sh)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data "$USER_DATA_SCRIPT" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"


##############
#    XMPP    #
#############
# mensajeria-1
INSTANCE_NAME="mensajeria-1"
SUBNET_ID="${SUBNET_PRIVATE1_ID}"
SECURITY_GROUP_ID="${SG_MENSAJERIA_ID}"
PRIVATE_IP="10.225.3.20"

#USER_DATA_SCRIPT=$(cat <<EOF
#EOF
#)

# INSTANCE_ID=$(aws ec2 run-instances \
#     --image-id "$AMI_ID" \
#     --instance-type "$INSTANCE_TYPE" \
#     --key-name "$KEY_NAME" \
#     --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
#     --network-interfaces "SubnetId=$SUBNET_ID,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
#     --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
#     --user-data "$USER_DATA_SCRIPT" \
#     --query "Instances[0].InstanceId" \
#     --output text)
# echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

# # mensajeria-2
# INSTANCE_NAME="mensajeria-2"
# PRIVATE_IP="10.225.3.30"

# INSTANCE_ID=$(aws ec2 run-instances \
#     --image-id "$AMI_ID" \
#     --instance-type "$INSTANCE_TYPE" \
#     --key-name "$KEY_NAME" \
#     --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
#     --network-interfaces "SubnetId=$SUBNET_ID,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
#     --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
#     --query "Instances[0].InstanceId" \
#     --output text)
# echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

##############
# WORDPRESS  #
##############
# soporte-1
INSTANCE_NAME="soporte-1"
SUBNET_ID="${SUBNET_PRIVATE2_ID}"
SECURITY_GROUP_ID="${SG_CMS_ID}"
PRIVATE_IP="10.225.4.10"

USER_DATA_SCRIPT=$(cat <<EOF
#!/bin/bash
##############################
#  INSTALACION WP / PLUGINS  #
##############################

# Variables
WP_PATH="/var/www/html"
WP_URL="https://srestrepoj-wordpress.duckdns.org"
ROLE_NAME="cliente_soporte"
SSL_CERT="/home/ubuntu/srestrepoj-wordpress.duckdns.org/fullchain.pem"
SSL_KEY="/home/ubuntu/srestrepoj-wordpress.duckdns.org/privkey.pem"
LOG_FILE="/var/log/wp_install.log"
# Funcion para registrar mensajes
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Funcion para esperar a que la base de datos esté disponible
wait_for_db() {
    log "Esperando a que la base de datos este disponible en $RDS_ENDPOINT..."
    while ! mysql -h "$RDS_ENDPOINT" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1" &>/dev/null; do
        log "Base de datos no disponible, esperando 10 segundos..."
        sleep 10
    done
    log "Base de datos disponible!"
}

# Esperar a que la base de datos esté disponible
wait_for_db

# Actualizar e instalar dependencias necesarias
log "Actualizando paquetes e instalando dependencias..."
sudo apt update
sudo apt install -y apache2 mysql-client php php-mysql libapache2-mod-php php-curl php-xml php-mbstring php-zip curl git unzip

# Instalar WP-CLI
log "Instalando WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Limpiar el directorio de Apache
log "Limpiando el directorio de Apache..."
sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R ubuntu:ubuntu /var/www/html

# Crear base de datos y usuario, si no existen
log "Creando base de datos y usuario (si no existe)..."
mysql -h $RDS_ENDPOINT -u $DB_USERNAME -p$DB_PASSWORD <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USERNAME'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USERNAME'@'%';
FLUSH PRIVILEGES;

# Descargar WordPress
log "Descargando WordPress..."
wp core download --path=/var/www/html

# Eliminar el archivo wp-config.php existente si hay uno
rm -f /var/www/html/wp-config.php

# Configurar wp-config.php
log "Configurando wp-config.php..."
wp core config --dbname="$DB_NAME" --dbuser="$DB_USERNAME" --dbpass="$DB_PASSWORD" --dbhost="$RDS_ENDPOINT" --dbprefix=wp_ --path=/var/www/html

# Instalar WordPress
log "Instalando WordPress..."
wp core install --url="$WP_URL" --title="CMS - TICKETING" --admin_user="$DB_USERNAME" --admin_password="$DB_PASSWORD" --admin_email="srestrepoj01@educantabria.es" --path=/var/www/html

# Instalar plugins adicionales
log "Instalando plugins..."
wp plugin install supportcandy --activate --path=/var/www/html
wp plugin install user-registration --activate --path=/var/www/html

# Crear paginas de registro y soporte
log "Creando paginas de registro y soporte..."
REGISTER_PAGE_ID=$(wp post create --post_title="Registro de Usuarios" --post_content="[user_registration_form]" --post_status="publish" --post_type="page" --path=/var/www/html --porcelain)
SUPPORT_PAGE_ID=$(wp post create --post_title="Soporte de Tickets" --post_content="[supportcandy]" --post_status="publish" --post_type="page" --path=/var/www/html --porcelain)

# Habilitar el registro de usuarios
wp option update users_can_register 1 --path=/var/www/html
wp option update default_role "subscriber" --path=/var/www/html

# Crear rol personalizado "Cliente de soporte"
log "Creando rol personalizado 'Cliente de soporte'..."
wp role create "$ROLE_NAME" "Cliente de soporte" --path=/var/www/html
wp role add_cap "$ROLE_NAME" "read" --path=/var/www/html
wp role add_cap "$ROLE_NAME" "create_ticket" --path=/var/www/html
wp role add_cap "$ROLE_NAME" "view_own_ticket" --path=/var/www/html

# Configurar Apache para WordPress con SSL
log "Configurando Apache para WordPress con SSL..."
sudo bash -c "cat > /etc/apache2/sites-available/wordpress.conf <<APACHE
<VirtualHost *:443>
    ServerAdmin admin@srestrepoj-wordpress.duckdns.org
    ServerName  srestrepoj-wordpress.duckdns.org

    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
APACHE"

# Habilitar el sitio de WordPress y reiniciar Apache
log "Reiniciando Apache..."
sudo a2dissite 000-default.conf
sudo a2ensite wordpress.conf
sudo a2enmod rewrite ssl
sudo systemctl restart apache2

log "¡Instalación completada! Accede a tu WordPress en: $WP_URL"

EOF
)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --network-interfaces "SubnetId=$SUBNET_ID,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --user-data "$USER_DATA_SCRIPT" \
    --query "Instances[0].InstanceId" \
    --output text)
echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

# # soporte-2
# INSTANCE_NAME="soporte-2"
# SUBNET_ID="${SUBNET_PRIVATE2_ID}"
# SECURITY_GROUP_ID="${SG_CMS_ID}"
# PRIVATE_IP="10.225.4.11"

# USER_DATA_SCRIPT=$(cat <<EOF
# #!/bin/#!/bin/bash
# set -e
# sudo apt update
# sudo apt install apache2 mysql-client mysql-server php php-mysql -y
# curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
# chmod +x wp-cli.phar
# sudo mv wp-cli.phar /usr/local/bin/wp
# sudo rm -rf /var/www/html/*
# sudo chmod -R 755 /var/www/html
# sudo chown -R ubuntu:ubuntu /var/www/html
# # MySQL credentials
# MYSQL_CMD="mysql -h ${RDS_ENDPOINT} -u ${DB_USERNAME} -p${DB_PASSWORD}"
# $MYSQL_CMD <<EOF2
# CREATE DATABASE IF NOT EXISTS ${DB_NAME};
# CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
# GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USERNAME}'@'%';
# FLUSH PRIVILEGES;
# EOF2
# sudo -u ubuntu -k -- wp core download --path=/var/www/html
# sudo -u ubuntu -k -- wp core config --dbname=${DB_NAME} --dbuser=${DB_USERNAME} --dbpass=${DB_PASSWORD} --dbhost=${RDS_ENDPOINT} --dbprefix=wp_ --path=/var/www/html
# sudo -u ubuntu -k -- wp core install --url=10.225.4.100  --title=Site_Title --admin_user=${DB_USERNAME} --admin_password=${DB_PASSWORD} --admin_email=majam02@educantabria.es --path=/var/www/html
# #sudo -u ubuntu -k -- wp option update home 'http://10.225.4.10' --path=/var/www/html
# #sudo -u ubuntu -k -- wp option update siteurl 'http://10.225.4.10' --path=/var/www/html
# sudo -u ubuntu -k -- wp plugin install supportcandy --activate --path=/var/www/html
# echo "WP configurado / montado"
# EOF
# )
# INSTANCE_ID=$(aws ec2 run-instances \
#     --image-id "$AMI_ID" \
#     --instance-type "$INSTANCE_TYPE" \
#     --key-name "$KEY_NAME" \
#     --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
#     --network-interfaces "SubnetId=$SUBNET_ID,DeviceIndex=0,PrivateIpAddresses=[{Primary=true,PrivateIpAddress=$PRIVATE_IP}],Groups=[$SECURITY_GROUP_ID]" \
#     --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
#     --user-data "$USER_DATA_SCRIPT" \
#     --query "Instances[0].InstanceId" \
#     --output text)
# echo "${INSTANCE_NAME} creada: ${INSTANCE_ID}"

