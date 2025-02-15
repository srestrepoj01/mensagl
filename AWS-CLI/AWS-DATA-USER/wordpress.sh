#!/bin/bash

# Actualizar el sistema y limpiar caché de APT
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update

# Instalar las dependencias de WordPress
sudo DEBIAN_FRONTEND=noninteractive apt install -y apache2 curl rsync git unzip ghostscript libapache2-mod-php mysql-server php php-bcmath php-curl php-imagick php-intl php-json php-mbstring php-mysql php-xml

# Descargar y configurar WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp-cli

# Limpiar el directorio web de nuestro servicio
sudo rm -rf /var/www/html/*
sudo chmod -R 755 /var/www/html
sudo chown -R www-data:www-data /var/www/html

# Reiniciar Apache para aplicar cambios
sudo a2enmod rewrite
sudo a2enmod ssl
sudo systemctl restart apache2

# Descargar y configurar WordPress
sudo -u www-data wp-cli core download --path='/var/www/html'
sudo -u www-data wp-cli core config --dbname=wordpress_db --dbuser=admin --dbpass=Admin123 --dbhost='wordpress-db.c1vddmtpdv5b.us-east-1.rds.amazonaws.com' --dbprefix=wp_ --path='/var/www/html'
sudo -u www-data wp-cli core install --url='https://srestrepoj-wp.duckdns.org' --title='Soporte - Sebastian' --admin_user='admin' --admin_password='Admin123' --admin_email='srestrepoj01@educantabria.es' --path='/var/www/html'

# Instalar y activar nuevos plugins
sudo -u www-data wp-cli plugin install awesome-support --activate --path='/var/www/html'
sudo -u www-data wp-cli plugin install user-registration --activate --path='/var/www/html'
sudo -u www-data wp-cli plugin install wps-hide-login --activate --path='/var/www/html'

# Crear páginas asociadas con los plugins
sudo -u www-data wp-cli post create --post_type=page --post_title="Enviar Ticket" --post_content="[awesome-support-submit-ticket]" --post_status=publish --path='/var/www/html' --porcelain
sudo -u www-data wp-cli post create --post_type=page --post_title="Panel de Soporte" --post_content="[awesome-support-tickets]" --post_status=publish --path='/var/www/html' --porcelain
sudo -u www-data wp-cli post create --post_title="Mi cuenta" --post_content="[user_registration_my_account]" --post_status="publish" --post_type="page" --path='/var/www/html' --porcelain

# Configuración de permisos y roles
sudo -u www-data wp-cli cap add "subscriber" "read" --path='/var/www/html'
sudo -u www-data wp-cli cap add "subscriber" "create_ticket" --path='/var/www/html'
sudo -u www-data wp-cli cap add "subscriber" "view_own_ticket" --path='/var/www/html'
sudo -u www-data wp-cli option update default_role "subscriber" --path='/var/www/html'

# Configuración de registro de usuarios
sudo -u www-data wp-cli option update users_can_register 1 --path='/var/www/html'

# Configuración de cabeceras para trabajar con HAProxy
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

# Configuración de VirtualHost en Apache para usar HTTPS con certificados SSL
cat << 'EOF' | sudo tee /etc/apache2/sites-available/wordpress-ssl.conf
<VirtualHost *:443>
    ServerName srestrepoj-wp.duckdns.org
    ServerAdmin srestrepoj01@educantabria.es

    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile /home/ubuntu/fullchain.pem
    SSLCertificateKeyFile /home/ubuntu/privkey.pem
    SSLCertificateChainFile /home/ubuntu/fullchain.pem

    # Habilitar la reescritura de URLs para WordPress
    <Directory /var/www/html>
        AllowOverride All
    </Directory>

</VirtualHost>
EOF

# Habilitar configuración de sitio y reiniciar Apache
sudo a2dissite 000-default.conf
sudo a2ensite wordpress-ssl.conf
sudo systemctl reload apache2