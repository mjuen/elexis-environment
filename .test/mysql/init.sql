CREATE DATABASE ee_elexis;
CREATE USER elexis@'%' IDENTIFIED BY 'elexis';
GRANT ALL PRIVILEGES ON ee_elexis.* TO 'elexis'@'%';
CREATE DATABASE ee_bookstack;
CREATE USER ee_bookstack@'%' IDENTIFIED BY 'ee_bookstack';
GRANT ALL PRIVILEGES ON ee_bookstack.* TO ee_bookstack@'%';
CREATE DATABASE ee_keycloak CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER ee_keycloak@'%' IDENTIFIED WITH mysql_native_password BY 'ee_keycloak';
GRANT ALL PRIVILEGES ON ee_keycloak.* TO ee_keycloak@'%';
FLUSH PRIVILEGES;