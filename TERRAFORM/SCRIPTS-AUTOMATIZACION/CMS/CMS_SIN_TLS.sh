#!/bin/bash
set -e

# Variables de Terraform
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASS=${db_pass}
DB_HOST=${db_host}
DB_PREFIX=${db_prefix}
SITE_URL=${site_url}
SITE_TITLE=${site_title}
ADMIN_USER=${admin_user}
ADMIN_PASSWORD=${admin_password}
ADMIN_EMAIL=${admin_email}

# Actualizar el sistema
sudo apt update

# Instalar Apache, MySQL y PHP
sudo apt install apache2 mysql-client mysql-server php php-mysql -y

# Descargar e instalar WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Limpiar el directorio web por defecto
sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R ubuntu:ubuntu /var/www/html

# Descargar y configurar WordPress
sudo -u ubuntu wp core download --path=/var/www/html
sudo -u ubuntu wp core config --dbname=$DB_NAME --dbuser=$DB_USER --dbpass=$DB_PASS --dbhost=$DB_HOST --dbprefix=$DB_PREFIX --path=/var/www/html
sudo -u ubuntu wp core install --url=$SITE_URL --title=$SITE_TITLE --admin_user=$ADMIN_USER --admin_password=$ADMIN_PASSWORD --admin_email=$ADMIN_EMAIL --path=/var/www/html

# Instalar y activar el plugin SupportCandy
sudo -u ubuntu wp plugin install supportcandy --activate --path=/var/www/html
