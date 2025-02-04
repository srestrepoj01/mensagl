 # INCLUIR ARCHIVO PARA LLAMAR VARIABLES
 source vpc_y_sg+rds.sh
##############################                       
#   Crear instancias EC2     #
##############################
LOG_FILE="laboratorio.log"


exec > "$LOG_FILE" 2>&1
# proxy-zona-1
INSTANCE_NAME="proxy-zona1"
SUBNET_ID="${SUBNET_PUBLIC1_ID}"
SECURITY_GROUP_ID="${SG_PROXY_ID}"
PRIVATE_IP="10.225.1.10"
INSTANCE_TYPE="t2.micro"
VOLUME_SIZE=8

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

# PROXY-2
INSTANCE_NAME="proxy-zona2"
SUBNET_ID="${SUBNET_PUBLIC2_ID}"
PRIVATE_IP="10.225.2.10"

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

USER_DATA_SCRIPT=$(cat <<EOF
#!/bin/bash
set -e
apt-get update -y
apt-get install mysql-server mysql-client -y
systemctl start mysql
systemctl enable mysql
mysql -e "CREATE DATABASE ${DB_NAME};"
mysql -e "CREATE USER '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USERNAME}'@'%';"
mysql -e "FLUSH PRIVILEGES;"
sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
sed -i "s/^mysqlx-bind-address\s*=.*/mysqlx-bind-address = 127.0.0.1/" /etc/mysql/mysql.conf.d/mysqld.cnf
echo "MySQL-DB-WORDPRESS CONFIGURADO"
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

# sgbd_secundario
INSTANCE_NAME="sgbd_replica-zona1"
PRIVATE_IP="10.225.3.11"

#AÑADIR SCRIPT Y ARREGLAR
USER_DATA_SCRIPT=$(cat <<EOF
#!/bin/bash
set -e
apt-get update -y
apt-get install mysql-server mysql-client -y
systemctl start mysql
systemctl enable mysql
mysql -e "CREATE DATABASE ${DB_NAME};"
mysql -e "CREATE USER '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';"
mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USERNAME}'@'%';"
mysql -e "FLUSH PRIVILEGES;"
sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
sed -i "s/^mysqlx-bind-address\s*=.*/mysqlx-bind-address = 127.0.0.1/" /etc/mysql/mysql.conf.d/mysqld.cnf
echo "MySQL-DB-WORDPRESS CONFIGURADO"
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

##############
#    XMPP    #
##############
# # xmpp-cluster-1
# INSTANCE_NAME="xmpp-cluster-1"
# SUBNET_ID="${SUBNET_PRIVATE1_ID}"
# SECURITY_GROUP_ID="${SG_MENSAJERIA_ID}"
# PRIVATE_IP="10.225.3.20"

# USER_DATA_SCRIPT=$(cat <<EOF
# #!/bin/bash
# apt-get update -y
# apt-get install prosody -y

# # Configuración básica de Prosody
# cat <<CONFIG > /etc/prosody/prosody.cfg.lua
# VirtualHost "xmpp.${DUCKDNS_SUBDOMAIN}.duckdns.org"
#     ssl = {
#         key = "/etc/prosody/certs/xmpp.${DUCKDNS_SUBDOMAIN}.duckdns.org.key";
#         certificate = "/etc/prosody/certs/xmpp.${DUCKDNS_SUBDOMAIN}.duckdns.org.crt";
#     }
#     modules_enabled = {
#         "roster";
#         "saslauth";
#         "tls";
#         "dialback";
#         "disco";
#         "carbons";
#         "pep";
#         "private";
#         "blocklist";
#         "vcard";
#         "version";
#         "uptime";
#         "time";
#         "ping";
#         "register";
#     }
# CONFIG

# # Crear certificados autofirmados (opcional, usar certificados válidos en producción)
# mkdir -p /etc/prosody/certs
# openssl req -new -x509 -days 365 -nodes -out "/etc/prosody/certs/xmpp.${DUCKDNS_SUBDOMAIN}.duckdns.org.crt" -keyout "/etc/prosody/certs/xmpp.${DUCKDNS_SUBDOMAIN}.duckdns.org.key" -subj "/CN=xmpp.${DUCKDNS_SUBDOMAIN}.duckdns.org"

# systemctl restart prosody
# systemctl enable prosody
# echo "XMPP PROSODY CONFIGURADO CORRECTAMENTE"
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

# # XMPP-2
# INSTANCE_NAME="xmpp-cluster-2"
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

# ##############
# # WORDPRESS  #
# ##############
# # cms-cluster-1
# INSTANCE_NAME="cms-cluster-1"
# SUBNET_ID="${SUBNET_PRIVATE2_ID}"
# SECURITY_GROUP_ID="${SG_CMS_ID}"
# PRIVATE_IP="10.225.4.10"

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

# # cms-cluster-2
# INSTANCE_NAME="cms-cluster-1"
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
