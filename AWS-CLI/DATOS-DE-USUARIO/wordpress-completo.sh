##########################################
#    SE CARGA DESDE "vpc_y_sg+rds,sh"    #
##########################################
#!/bin/bash
set -e

# Actualizar e instalar dependencias necesarias
sudo apt update
sudo apt install -y apache2 mysql-client php php-mysql libapache2-mod-php php-curl php-xml php-mbstring php-zip curl git unzip

# Instalar WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Limpiar el directorio de Apache
sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R ubuntu:ubuntu /var/www/html

# Configurar la base de datos en RDS
mysql -h "${RDS_ENDPOINT}" -u "${DB_USERNAME}" -p"${DB_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USERNAME}'@'%';
FLUSH PRIVILEGES;
SQL

# Descargar WordPress
wp core download --path=/var/www/html

# Configurar wp-config.php
wp core config --dbname="${DB_NAME}" --dbuser="${DB_USERNAME}" --dbpass="${DB_PASSWORD}" --dbhost="${RDS_ENDPOINT}" --dbprefix="wp_" --path=/var/www/html

# Instalar WordPress
wp core install --url="http://${PRIVATE_IP}" --title="Mi WordPress" --admin_user="${DB_USERNAME}" --admin_password="${DB_PASSWORD}" --admin_email="admin@example.com" --path=/var/www/html

# Instalar plugins adicionales
wp plugin install supportcandy --activate --path=/var/www/html
wp plugin install user-registration --activate --path=/var/www/html

# Configurar Apache para WordPress
sudo bash -c "cat > /etc/apache2/sites-available/wordpress.conf <<APACHE
<VirtualHost *:80>
    ServerName ${PRIVATE_IP}
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
APACHE"

# Habilitar el sitio de WordPress y reiniciar Apache
sudo a2dissite 000-default.conf
sudo a2ensite wordpress.conf
sudo a2enmod rewrite
sudo systemctl restart apache2
