#!/bin/bash

# Variables
NOMBRE_ALUMNO="equipo5" # Cambiar por la que sea del alumno
REGION="us-east-1"

# Crear clave SSH
aws ec2 create-key-pair \
    --key-name "ssh-mensagl-2025-${NOMBRE_ALUMNO}" \
    --query 'KeyMaterial' \
    --output text > "ssh-mensagl-2025-${NOMBRE_ALUMNO}.pem"
chmod 400 "ssh-mensagl-2025-${NOMBRE_ALUMNO}.pem"

# Crear VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block "10.0.0.0/16" --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-vpc"

# Crear Subnets publicas
SUBNET_PUBLIC1_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.1.0/24" --availability-zone "${REGION}a" --query 'Subnet.SubnetId' --output text)
SUBNET_PUBLIC2_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.2.0/24" --availability-zone "${REGION}b" --query 'Subnet.SubnetId' --output text)

# Crear Subnets privadas
SUBNET_PRIVATE1_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.3.0/24" --availability-zone "${REGION}a" --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE2_ID=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "10.0.4.0/24" --availability-zone "${REGION}b" --query 'Subnet.SubnetId' --output text)

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

# Crear Grupos de Seguridad

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
aws ec2 authorize-security-group-ingress --group-id "$SG_MYSQL_ID" --protocol tcp --port 3306 --cidr "$(aws ec2 describe-subnets --subnet-ids "$SUBNET_PRIVATE2_ID" --query 'Subnets[0].CidrBlock' --output text)"
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

# Grupo de seguridad para Jitsi
SG_JITSI_ID=$(aws ec2 create-security-group --group-name "sg_jitsi" --description "SG para Jitsi Meet y Videobridge" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_JITSI_ID" --protocol udp --port 10000 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-ingress --group-id "$SG_JITSI_ID" --protocol tcp --port 5347 --source-group "$SG_MENSAJERIA_ID"
aws ec2 authorize-security-group-egress --group-id "$SG_JITSI_ID" --protocol -1 --port all --cidr "0.0.0.0/0"

# Grupo de seguridad para RDS MySQL
SG_RDS_MYSQL_ID=$(aws ec2 create-security-group --group-name "sg_rds_mysql" --description "SG para el RDS del CMS" --vpc-id "$VPC_ID" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_RDS_MYSQL_ID" --protocol tcp --port 3306 --cidr "0.0.0.0/0"
aws ec2 authorize-security-group-egress --group-id "$SG_RDS_MYSQL_ID" --protocol -1 --port all --cidr "0.0.0.0/0"