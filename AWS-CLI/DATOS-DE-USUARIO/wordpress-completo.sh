#!/bin/bash
# Instalación de WordPress, SupportCandy, User Registration, configuración de rol personalizado "Cliente de soporte" y configuracion de DuckDNS con SSL.
# Variables
WP_PATH="/var/www/html/wordpress"
WP_DB="wordpressdb" 
WP_USER="wordpressuser"
WP_PASS="password"
WP_URL="https://reto5.duckdns.org"
ROLE_NAME="cliente_soporte"
DUCKDNS_DOMAIN="reto5.duckdns.org"
DUCKDNS_TOKEN="f319b7f5-243b-4e0d-97fa-aeb74fa0b440"

# Actualizar paquetes e instalar dependencias
echo "\U0001F4E6 Actualizando paquetes e instalando dependencias..."
sudo apt-get update && sudo apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql php-curl php-xml php-mbstring php-zip curl git unzip software-properties-common certbot python3-certbot-apache

# Iniciar y habilitar servicios
echo "\U0001F680 Iniciando Apache y MySQL..."
sudo systemctl enable --now apache2
sudo systemctl enable --now mysql

# Configurar MySQL y crear base de datos
echo "\U0001F465 Configurando MySQL..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS $WP_DB;"
sudo mysql -e "CREATE USER IF NOT EXISTS '$WP_USER'@'localhost' IDENTIFIED BY '$WP_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $WP_DB.* TO '$WP_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Descargar e instalar WP-CLI
echo "\U0001F527 Instalando WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp

# Descargar WordPress
echo "\U0001F4E5 Descargando WordPress..."
wget https://wordpress.org/latest.tar.gz
tar -xvzf latest.tar.gz
sudo mv wordpress $WP_PATH
sudo chown -R www-data:www-data $WP_PATH

# Configurar wp-config.php
echo "⚙️ Configurando WordPress..."
sudo cp $WP_PATH/wp-config-sample.php $WP_PATH/wp-config.php
sudo sed -i "s/database_name_here/$WP_DB/" $WP_PATH/wp-config.php
sudo sed -i "s/username_here/$WP_USER/" $WP_PATH/wp-config.php
sudo sed -i "s/password_here/$WP_PASS/" $WP_PATH/wp-config.php
echo "define('WP_HOME', '$WP_URL');" | sudo tee -a $WP_PATH/wp-config.php > /dev/null
echo "define('WP_SITEURL', '$WP_URL');" | sudo tee -a $WP_PATH/wp-config.php > /dev/null

# Configurar Apache
echo "\U0001F310 Configurando Apache para WordPress..."
sudo bash -c 'cat > /etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost *:80>
    ServerName '$DUCKDNS_DOMAIN'
    DocumentRoot /var/www/html/wordpress
    <Directory /var/www/html/wordpress>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF'

sudo a2dissite 000-default.conf
sudo a2ensite wordpress.conf
sudo a2enmod rewrite
sudo systemctl restart apache2

# Instalar WordPress con WP-CLI
echo "📝 Instalando WordPress..."
sudo -u www-data wp core install --path=$WP_PATH --url=$WP_URL --title="Mi WordPress" --admin_user="admin" --admin_password="adminpassword" --admin_email="admin@example.com"

# Corregir permisos de WP-CLI
echo "🔑 Corrigiendo permisos de caché de WP-CLI..."
sudo mkdir -p /var/www/.wp-cli/cache
sudo chown -R www-data:www-data /var/www/.wp-cli

# INSTALACIÓN DE SUPPORTCANDY
echo "📥 Instalando SupportCandy..."
sudo -u www-data wp plugin install supportcandy --activate --path=$WP_PATH

# INSTALACIÓN DE USER REGISTRATION
echo "📥 Instalando User Registration..."
sudo -u www-data wp plugin install user-registration --activate --path=$WP_PATH

# Crear páginas de registro y soporte
echo "📝 Creando páginas de registro y soporte..."
REGISTER_PAGE_ID=$(sudo -u www-data wp post create --post_title="Registro de Usuarios" --post_content="[user_registration_form]" --post_status="publish" --post_type="page" --path=$WP_PATH --porcelain)
SUPPORT_PAGE_ID=$(sudo -u www-data wp post create --post_title="Soporte de Tickets" --post_content="[supportcandy]" --post_status="publish" --post_type="page" --path=$WP_PATH --porcelain)

# Habilitar el registro de usuarios
echo "🔓 Configurando opciones de registro..."
sudo -u www-data wp option update users_can_register 1 --path=$WP_PATH
sudo -u www-data wp option update default_role "subscriber" --path=$WP_PATH

# Crear rol personalizado "Cliente de soporte"
echo "⚙️ Creando rol personalizado 'Cliente de soporte'..."
sudo -u www-data wp role create "$ROLE_NAME" "Cliente de soporte" --path=$WP_PATH
sudo -u www-data wp role add_cap "$ROLE_NAME" "read" --path=$WP_PATH
sudo -u www-data wp role add_cap "$ROLE_NAME" "create_ticket" --path=$WP_PATH
sudo -u www-data wp role add_cap "$ROLE_NAME" "view_own_ticket" --path=$WP_PATH

# Configurar DuckDNS
echo "🔄 Instalando y configurando DuckDNS..."
mkdir -p /home/ubuntu/duckdns
echo "echo url=\"https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCKDNS_TOKEN&ip=\" | curl -k -o /dev/null -K -" > /home/ubuntu/duckdns/duck.sh
chmod +x /home/ubuntu/duckdns/duck.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /home/ubuntu/duckdns/duck.sh >/dev/null 2>&1") | crontab -

# Configuración de Let's Encrypt
echo "🔒 Instalando certificado SSL..."
sudo certbot --apache -d $DUCKDNS_DOMAIN --non-interactive --agree-tos -m admin@example.com

# Mensaje de éxito
echo "✅ Instalación completada. Accede a tu WordPress en: $WP_URL"

