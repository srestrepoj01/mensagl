#!/bin/bash
set -x  # Activar modo de depuración

# Variables
role="$1"  # "primary" o "secondary"
primary_ip="10.225.3.10"
secondary_ip="10.225.3.11"
db_user="admin"
db_password="Admin123"
db_name="prosody"
repl_user="replica"
repl_password="Admin123"

# 1. Instalar MySQL
sudo apt-get update > /dev/null
sudo apt-get install -y mysql-server mysql-client > /dev/null

# 2. Configurar replicación
sudo tee /etc/mysql/mysql.conf.d/replication.cnf > /dev/null <<EOF
[mysqld]
bind-address = 0.0.0.0
server-id = $( [ "$role" = "primary" ] && echo 1 || echo 2 )
log_bin = /var/log/mysql/mysql-bin.log
binlog_format = ROW
relay-log = /var/log/mysql/mysql-relay-bin
EOF

# 3. Reiniciar servicio
sudo systemctl restart mysql

# 4. Configuración básica de seguridad
sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$db_password';
DELETE FROM mysql.user WHERE User='';
CREATE DATABASE IF NOT EXISTS $db_name;
FLUSH PRIVILEGES;
EOF

# 5. Configuración específica por rol
if [ "$role" = "primary" ]; then
    sudo mysql -u root -p$db_password <<EOF
    CREATE USER '$db_user'@'%' IDENTIFIED WITH mysql_native_password BY '$db_password';
    GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'%';
    CREATE USER '$repl_user'@'%' IDENTIFIED WITH mysql_native_password BY '$repl_password';
    GRANT REPLICATION SLAVE ON *.* TO '$repl_user'@'%';
    FLUSH PRIVILEGES;
EOF

    # Obtener posición del binlog
    sudo mysql -u root -p$db_password -e "SHOW MASTER STATUS" | awk 'NR==2 {print $1, $2}' > /tmp/master_status.txt

elif [ "$role" = "secondary" ]; then
    # Esperar conexión con primario
    until nc -z $primary_ip 3306; do sleep 10; done

    # Leer el estado del binlog desde el primario
    MASTER_STATUS=$(sshpass -p 'tu_contraseña' ssh -o StrictHostKeyChecking=no ubuntu@$primary_ip "mysql -u root -p$db_password -e 'SHOW MASTER STATUS' | awk 'NR==2 {print \$1, \$2}'")
    binlog_file=$(echo "$MASTER_STATUS" | awk '{print $1}')
    binlog_pos=$(echo "$MASTER_STATUS" | awk '{print $2}')

    sudo mysql -u root -p$db_password <<EOF
    CHANGE MASTER TO
    MASTER_HOST='$primary_ip',
    MASTER_USER='$repl_user',
    MASTER_PASSWORD='$repl_password',
    MASTER_LOG_FILE='$binlog_file',
    MASTER_LOG_POS=$binlog_pos;
    START SLAVE;
EOF
fi

# 6. Habilitar servicio
sudo systemctl enable mysql > /dev/null
