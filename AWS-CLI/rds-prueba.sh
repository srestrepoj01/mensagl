 # INCLUIR ARCHIVO PARA LLAMAR VARIABLES
 source vpc_y_sg+rds.sh
 
##############################                       
#             RDS             #
##############################

# Crear subnet RDS (ya la tenías definida)
aws rds create-db-subnet-group \
    --db-subnet-group-name wp-rds-subnet-group \
    --db-subnet-group-description "RDS Subnet Group for WordPress" \
    --subnet-ids "$SUBNET_PRIVATE1_ID" "$SUBNET_PRIVATE2_ID"

# Permite acceso a MySQL en el grupo de seguridad existente
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
