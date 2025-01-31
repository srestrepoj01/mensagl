#!/bin/bash

# Variables
NOMBRE_ALUMNO="sebastian" # CAMBIAR POR NOMBRE DESEADO
REGION="us-east-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_PUBLIC1_CIDR="10.0.1.0/24"
SUBNET_PUBLIC2_CIDR="10.0.2.0/24"
SUBNET_PRIVATE1_CIDR="10.0.3.0/24"
SUBNET_PRIVATE2_CIDR="10.0.4.0/24"
AVAILABILITY_ZONE1="us-east-1a"
AVAILABILITY_ZONE2="us-east-1b"
KEY_NAME="ssh-mensagl-2025-${NOMBRE_ALUMNO}"
PRIVATE_KEY_FILE="ssh-mensagl-2025-${NOMBRE_ALUMNO}.pem"

#########################
#                       #
# Crear clave SSH       #
#                       #
#########################

# Generar clave SSH localmente
echo "Generando clave SSH..."
ssh-keygen -t rsa -b 2048 -f $PRIVATE_KEY_FILE -N "" -q

# Extraer la clave publica
PUBLIC_KEY=$(cat ${PRIVATE_KEY_FILE}.pub)

# Crear clave SSH en AWS
echo "Creando clave SSH en AWS..."
aws ec2 import-key-pair \
    --key-name $KEY_NAME \
    --public-key-material "$PUBLIC_KEY" \
    --region $REGION

echo "Clave SSH creada en AWS con el nombre: $KEY_NAME"
echo "Clave privada guardada en: $PRIVATE_KEY_FILE"

#########################
#                        #
# Crear VPC y Subnets    #
#                        #
#########################

# Crear VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $REGION --query 'Vpc.VpcId' --output text)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}" --region $REGION

# Habilitar DNS support y DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support --region $REGION
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames --region $REGION

# Crear Subnets Publicas
SUBNET_PUBLIC1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_PUBLIC1_CIDR --availability-zone $AVAILABILITY_ZONE1 --region $REGION --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUBNET_PUBLIC1_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-subnet-public1-${AVAILABILITY_ZONE1}" --region $REGION

SUBNET_PUBLIC2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_PUBLIC2_CIDR --availability-zone $AVAILABILITY_ZONE2 --region $REGION --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUBNET_PUBLIC2_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-subnet-public2-${AVAILABILITY_ZONE2}" --region $REGION

# Crear Subnets Privadas
SUBNET_PRIVATE1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_PRIVATE1_CIDR --availability-zone $AVAILABILITY_ZONE1 --region $REGION --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUBNET_PRIVATE1_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-subnet-private1-${AVAILABILITY_ZONE1}" --region $REGION

SUBNET_PRIVATE2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_PRIVATE2_CIDR --availability-zone $AVAILABILITY_ZONE2 --region $REGION --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources $SUBNET_PRIVATE2_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-subnet-private2-${AVAILABILITY_ZONE2}" --region $REGION

########################################
#                                      #
# Crear Internet Gateway y NAT Gateway #
#                                      #
########################################

# Crear Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway --region $REGION --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-igw" --region $REGION
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $REGION

# Crear Elastic IP para NAT Gateway
EIP_ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --region $REGION --query 'AllocationId' --output text)
aws ec2 create-tags --resources $EIP_ALLOCATION_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-eip" --region $REGION

# Crear NAT Gateway
NAT_GATEWAY_ID=$(aws ec2 create-nat-gateway --subnet-id $SUBNET_PUBLIC1_ID --allocation-id $EIP_ALLOCATION_ID --region $REGION --query 'NatGateway.NatGatewayId' --output text)
aws ec2 create-tags --resources $NAT_GATEWAY_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-nat" --region $REGION

#########################
#                                                 #
# Crear Route Tables                 #
#                                                 #
#########################

# Crear Route Table Publica
ROUTE_TABLE_PUBLIC_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $ROUTE_TABLE_PUBLIC_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-rtb-public" --region $REGION
aws ec2 create-route --route-table-id $ROUTE_TABLE_PUBLIC_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION

# Asociar Subnets Publicas a la Route Table Publica
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PUBLIC_ID --subnet-id $SUBNET_PUBLIC1_ID --region $REGION
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PUBLIC_ID --subnet-id $SUBNET_PUBLIC2_ID --region $REGION

# Crear Route Tables Privadas
ROUTE_TABLE_PRIVATE1_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $ROUTE_TABLE_PRIVATE1_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-rtb-private1-${AVAILABILITY_ZONE1}" --region $REGION
aws ec2 create-route --route-table-id $ROUTE_TABLE_PRIVATE1_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GATEWAY_ID --region $REGION

ROUTE_TABLE_PRIVATE2_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --region $REGION --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-tags --resources $ROUTE_TABLE_PRIVATE2_ID --tags Key=Name,Value="vpc-mensagl-2025-${NOMBRE_ALUMNO}-rtb-private2-${AVAILABILITY_ZONE2}" --region $REGION
aws ec2 create-route --route-table-id $ROUTE_TABLE_PRIVATE2_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GATEWAY_ID --region $REGION

# Asociar Subnets Privadas a las Route Tables Privadas
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PRIVATE1_ID --subnet-id $SUBNET_PRIVATE1_ID --region $REGION
aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_PRIVATE2_ID --subnet-id $SUBNET_PRIVATE2_ID --region $REGION

#########################
#                       #
# Crear Security Groups #
#                       #
#########################

# Crear Security Group para Proxy Inverso
SG_PROXY_ID=$(aws ec2 create-security-group --group-name "sg_proxy_inverso" --description "SG para el proxy inverso" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_PROXY_ID --tags Key=Name,Value="sg_proxy_inverso" --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 8448 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-egress --group-id $SG_PROXY_ID --protocol all --port all --cidr 0.0.0.0/0 --region $REGION

# Crear Security Group para CMS
SG_CMS_ID=$(aws ec2 create-security-group --group-name "sg_cms" --description "SG para el cluster CMS" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_CMS_ID --tags Key=Name,Value="sg_cms" --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 33060 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_CMS_ID --protocol tcp --port 53 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-egress --group-id $SG_CMS_ID --protocol all --port all --cidr 0.0.0.0/0 --region $REGION

# Crear Security Group para MySQL
SG_MYSQL_ID=$(aws ec2 create-security-group --group-name "sg_mysql" --description "SG para servidores MySQL" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_MYSQL_ID --tags Key=Name,Value="sg_mysql" --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MYSQL_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MYSQL_ID --protocol tcp --port 3306 --cidr $SUBNET_PRIVATE1_CIDR --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MYSQL_ID --protocol tcp --port 3306 --cidr $SUBNET_PRIVATE2_CIDR --region $REGION
aws ec2 authorize-security-group-egress --group-id $SG_MYSQL_ID --protocol all --port all --cidr 0.0.0.0/0 --region $REGION

# Crear Security Group para Mensajeria (XMPP Prosody + MySQL)
SG_MENSAJERIA_ID=$(aws ec2 create-security-group --group-name "sg_mensajeria" --description "SG para XMPP Prosody y MySQL" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_MENSAJERIA_ID --tags Key=Name,Value="sg_mensajeria" --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MENSAJERIA_ID --protocol tcp --port 5222 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MENSAJERIA_ID --protocol tcp --port 5347 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_MENSAJERIA_ID --protocol tcp --port 3306 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-egress --group-id $SG_MENSAJERIA_ID --protocol all --port all --cidr 0.0.0.0/0 --region $REGION

# Crear Security Group para Jitsi
SG_JITSI_ID=$(aws ec2 create-security-group --group-name "sg_jitsi" --description "SG para Jitsi Meet y Videobridge" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_JITSI_ID --tags Key=Name,Value="sg_jitsi" --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_JITSI_ID --protocol udp --port 10000 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_JITSI_ID --protocol tcp --port 5347 --source-group $SG_MENSAJERIA_ID --region $REGION
aws ec2 authorize-security-group-egress --group-id $SG_JITSI_ID --protocol all --port all --cidr 0.0.0.0/0 --region $REGION

# Crear Security Group para RDS MySQL
SG_RDS_MYSQL_ID=$(aws ec2 create-security-group --group-name "sg_rds_mysql" --description "SG para el RDS del CMS" --vpc-id $VPC_ID --region $REGION --query 'GroupId' --output text)
aws ec2 create-tags --resources $SG_RDS_MYSQL_ID --tags Key=Name,Value="sg_rds" --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_RDS_MYSQL_ID --protocol tcp --port 3306 --cidr 0.0.0.0/0 --region $REGION

echo "Infraestructura creada exitosamente."