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

# Variables DDNS
# read -r -p "Ingrese el TOKEN de DDNS: " DUCKDNS_TOKEN
# read -r -p "Ingrese el primer subdominio (proxy-1): " DUCKDNS_SUBDOMAIN
# read -r -p "Ingrese el segundo subdominio (proxy-2): " DUCKDNS_SUBDOMAIN2

# Variables AMI-ID (Ubuntu server 24.04) y CLAVE SSH
KEY_NAME="ssh-mensagl-2025-${NOMBRE_ALUMNO}"
AMI_ID="ami-04b4f1a9cf54c11d0" # Llamar variable claves         

# Crear par de claves SSH
aws ec2 create-key-pair \
    --key-name "${KEY_NAME}" \
    --query "KeyMaterial" \
    --output text > "${KEY_NAME}.pem"
chmod 400 "${KEY_NAME}.pem"
echo "Clave SSH creada: ${KEY_NAME}.pem"


# Variables para RDS, se pueden cambiar los valores por los deseados
RDS_INSTANCE_ID="wordpress-db"
read -r -p "Ingrese el nombre de la base de datos: " DB_NAME
read -r -p "Ingrese el nombre de usuario de la BD: " DB_USERNAME
read -r -p "Ingrese la contraseña de la BD: " DB_PASSWORD


exec > "$LOG_FILE" 2>&1

##############################                       
#             VPC             #
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

# Grupo de seguridad para los Proxy Inversos
SG_PROXY_ID=$(aws ec2 create-security-group --group-name "sg_proxy_inverso" --description "SG para el proxy inverso" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_ID" --protocol tcp --port 22 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_ID" --protocol tcp --port 443 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_PROXY_ID" --protocol tcp --port 8448 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-egress --group-id "$SG_PROXY_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

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

# Crear subnet RDS (ya la tenías definida)
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
