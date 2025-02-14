#!/bin/bash
set -e

# Actualizar el sistema
sudo apt update

# Instalar Prosody y MySQL
sudo apt install prosody mysql-server lua-dbi-mysql -y

# Configurar MySQL para Prosody
sudo mysql -u root <<EOF
CREATE DATABASE prosody;
CREATE USER 'admin'@'localhost' IDENTIFIED BY 'Admin123';
GRANT ALL PRIVILEGES ON prosody.* TO 'admin'@'localhost';
FLUSH PRIVILEGES;
EOF

# Configurar Prosody
sudo tee /etc/prosody/prosody.cfg.lua > /dev/null <<EOL
-- Prosody Example Configuration File
-- Information on configuring Prosody can be found on our website
-- at http://prosody.im/doc/configure

admins = { "admin@localhost" }

modules_enabled = {
    "roster"; -- Allow users to have a roster. Recommended :)
    "saslauth"; -- Authentication for clients and servers. Recommended if you want to log in.
    "tls"; -- Add support for secure TLS on c2s/s2s connections
    "dialback"; -- s2s dialback support
    "disco"; -- Service discovery

    "posix"; -- POSIX functionality, sends server to background, enables syslog, etc.
    "private"; -- Private XML storage (for room bookmarks, etc.)
    "vcard"; -- Allow users to set vCards
    "version"; -- Replies to server version requests
    "uptime"; -- Report how long server has been running
    "time"; -- Let others know the time here on this server
    "ping"; -- Replies to XMPP pings with pongs
    "register"; -- Allow users to register on this server using a client and change passwords
    "admin_adhoc"; -- Allows administration via an XMPP client that supports ad-hoc commands
    "admin_web"; -- Admin Web interface
}

modules_disabled = {
    -- "offline"; -- Store offline messages
    -- "c2s"; -- Handle client connections
    -- "s2s"; -- Handle server-to-server connections
}

allow_registration = true;

daemonize = true;

pidfile = "/var/run/prosody/prosody.pid";

c2s_require_encryption = false
s2s_require_encryption = false

-- Logging configuration
log = {
    info = "/var/log/prosody/prosody.log"; -- Change 'info' to 'debug' for more verbose logging
    error = "/var/log/prosody/prosody.err";
    "*syslog"; -- Uncomment this for logging to syslog
}

-- MySQL storage backend
storage = "sql" -- Default is "internal"
sql = {
    driver = "MySQL";
    database = "prosody";
    username = "admin";
    password = "Admin123";
    host = "localhost";
}
EOL

# Reiniciar Prosody
sudo systemctl restart prosody
