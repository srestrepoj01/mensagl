#!/bin/bash
# Actualizar el sistema
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt install -y apache2 curl git unzip ghostscript libapache2-mod-php mysql-server php php-bcmath php-curl php-imagick php-intl php-json php-mbstring php-mysql php-xml

# Instalar las dependencias de WordPress
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
# Instalar las dependencias de WordPress
sudo DEBIAN_FRONTEND=noninteractive apt install -y apache2 curl rsync git unzip ghostscript libapache2-mod-php mysql-server php php-bcmath php-curl php-imagick php-intl php-json php-mbstring php-mysql php-xml

# Instalar WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp-cli

# Limpiar el directorio web de nuestro servicio
sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R www-data:www-data /var/www/html

# Reiniciar Apache para aplicar cambios
sudo a2enmod rewrite
sudo systemctl restart apache2

# Descargar y configurar WordPress
sudo -u www-data wp-cli core download --path=/var/www/html
sudo -u www-data wp-cli core config --dbname=wordpress --dbuser=${DB_USERNAME} --dbpass=${DB_PASSWORD} --dbhost=${RDS_ENDPOINT} --dbprefix=wp --path=/var/www/html
sudo -u www-data wp-cli core install --url='https://srestrepoj-wp.duckdns.org' --title='Wordpress equipo 4' --admin_user='equipo4' --admin_password='_Admin123' --admin_email='admin@example.com' --path=/var/www/html

# Instalar y activar plugins
sudo -u www-data wp-cli plugin install supportcandy --activate --path='/var/www/html'
sudo -u www-data wp-cli plugin install user-registration --activate --path='/var/www/html'
sudo -u www-data wp-cli plugin install wps-hide-login --activate
sudo -u www-data wp-cli option update wps_hide_login_url equipo4-admin

# Configurar roles y permisos
sudo -u www-data wp-cli cap add "subscriber" "read" --path=/var/www/html
sudo -u www-data wp-cli cap add "subscriber" "create_ticket" --path=/var/www/html
sudo -u www-data wp-cli cap add "subscriber" "view_own_ticket" --path=/var/www/html
sudo -u www-data wp-cli option update default_role "subscriber" --path=/var/www/html

# Habilitar registros y formularios
sudo -u www-data wp-cli option update users_can_register 1 --path=/var/www/html
sudo -u www-data wp-cli post create --post_title="Mi cuenta" --post_content="[user_registration_my_account]" --post_status="publish" --post_type="page" --path=/var/www/html --porcelain
sudo -u www-data wp-cli post create --post_title="Registro" --post_content="[user_registration_form id="9"]" --post_status="publish" --post_type="page" --path=/var/www/html --porcelain
sudo -u www-data wp-cli post create --post_title="Tickets" --post_content="[supportcandy]" --post_status="publish" --post_type="page" --path=/var/www/html --porcelain

# Ajustar configuración de wp-config.php
sudo sed -i '1d' /var/www/html/wp-config.php
sudo sed -i '1i\
<?php if (isset($_SERVER["HTTP_X_FORWARDED_FOR"])) {\
    $list = explode(",", $_SERVER["HTTP_X_FORWARDED_FOR"]);\
    $_SERVER["REMOTE_ADDR"] = $list[0];\
}\
$_SERVER["HTTP_HOST"] = "srestrepoj-wp.duckdns.org";\
$_SERVER["REMOTE_ADDR"] = "srestrepoj-wp.duckdns.org";\
$_SERVER["SERVER_ADDR"] = "srestrepoj-wp.duckdns.org";\
' /var/www/html/wp-config.php

# Configurar SSL
sudo scp -i clave.pem -o StrictHostKeyChecking=no ubuntu@10.212.2.10:/home/ubuntu/certwordpress/* /home/ubuntu/
sudo cp /home/ubuntu/default-ssl.conf /etc/apache2/sites-available/default-ssl.conf
sudo a2enmod ssl
sudo a2enmod headers
sudo a2ensite default-ssl.conf
sudo a2dissite 000-default.conf
sudo systemctl reload apache2
