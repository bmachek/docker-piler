#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DATAROOTDIR="/usr/share"
SYSCONFDIR="/etc"
SPHINXCFG="/etc/piler/sphinx.conf"
PILER_HOST=${PILER_HOST:-archive.yourdomain.com}
CONFIG_SITE_PHP="/etc/piler/config-site.php"
CONFIG_PHP="/var/piler/www/config.php"

create_dir_if_not_exist() {
   [[ -d $1 ]] || mkdir $1
}

create_mysql_db() {
   echo "Creating mysql database"
   mysql -N -s -h"$MYSQL_HOSTNAME" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE"  -e "drop database ${MYSQL_DATABASE};"
   sed -e "s%MYSQL_HOSTNAME%${MYSQL_HOSTNAME}%g" \
       -e "s%MYSQL_DATABASE%${MYSQL_DATABASE}%g" \
       -e "s%MYSQL_USERNAME%${MYSQL_USER}%g" \
       -e "s%MYSQL_PASSWORD%${MYSQL_PASSWORD}%g" \
       "${DATAROOTDIR}/piler/db-mysql-root.sql.in" | \
       mysql --host="${MYSQL_HOSTNAME}" --user=root --password="${MYSQL_ROOT_PASSWORD}"
    
   mysql --host="${MYSQL_HOSTNAME}" --user="${MYSQL_USER}" --password="${MYSQL_PASSWORD}" "$MYSQL_DATABASE" < "${DATAROOTDIR}/piler/db-mysql.sql"
   echo "Done."
}


pre_seed_sphinx() {
   echo "Writing sphinx configuration"

   sed -e "s%MYSQL_HOSTNAME%${MYSQL_HOSTNAME}%" \
       -e "s%MYSQL_DATABASE%${MYSQL_DATABASE}%" \
       -e "s%MYSQL_USERNAME%${MYSQL_USER}%" \
       -e "s%MYSQL_PASSWORD%${MYSQL_PASSWORD}%" \
       -e "s%@LOCALSTATEDIR@%/var%" \
       -e "s%type = mysql%type = mysql%" \
       -e "s%331%221%" \
       -e "s%thread_pool%threads%" \
       "/etc/piler/sphinx.conf.dist" > "/etc/piler/sphinx.conf"

   echo "Done."

   echo "Initializing sphinx indices"
   su "$PILER_USER" -c "indexer --rotate --all --config /etc/piler/sphinx.conf" && true
   echo "Done."
}


fix_configs() {
   local piler_nginx_conf="/etc/piler/piler-nginx.conf"

   if [[ ! -f "/etc/piler/piler.conf" ]]; then
      cp /etc/piler/piler.conf.dist "/etc/piler/piler.conf"
      chmod 640 "/etc/piler/piler.conf"
      chown root:piler "/etc/piler/piler.conf"
      sed -i "s%hostid=.*%hostid=${PILER_HOST%%:*}%" "/etc/piler/piler.conf"
      sed -i "s%tls_enable=.*%tls_enable=1%" "/etc/piler/piler.conf"
      sed -i "s%mysqlsocket=.*%mysqlsocket=\nmysqlhost=${MYSQL_HOSTNAME}\nmysqlport=3306%" "/etc/piler/piler.conf"
      sed -i "s%mysqlpwd=.*%mysqlpwd=${MYSQL_PASSWORD}%" "/etc/piler/piler.conf"
      grep mysql /etc/piler/piler.conf
   fi

   if [[ ! -f "$piler_nginx_conf" ]]; then
      cp /piler-nginx.conf.dist "$piler_nginx_conf"
      sed -i "s%PILER_HOST%${PILER_HOST}%" "$piler_nginx_conf"
   fi

   ln -sf "$piler_nginx_conf" /etc/nginx/sites-enabled/piler

   sed -i "s%HOSTNAME%${PILER_HOST}%" "$CONFIG_SITE_PHP"
   sed -i "s%MYSQL_PASSWORD%${MYSQL_PASSWORD}%" "$CONFIG_SITE_PHP"

   sed -i "s%^\$config\['DECRYPT_BINARY'\].*%\$config\['DECRYPT_BINARY'\] = '/usr/bin/pilerget';%" "$CONFIG_PHP"
   sed -i "s%^\$config\['DECRYPT_ATTACHMENT_BINARY'\].*%\$config\['DECRYPT_ATTACHMENT_BINARY'\] = '/usr/bin/pileraget';%" "$CONFIG_PHP"
   sed -i "s%^\$config\['PILER_BINARY'\].*%\$config\['PILER_BINARY'\] = '/usr/sbin/piler';%" "$CONFIG_PHP"
   sed -i "s%^\$config\['DB_HOSTNAME'\].*%\$config\['DB_HOSTNAME'\] = '${MYSQL_HOSTNAME}';%" "$CONFIG_PHP"
}

create_dir_if_not_exist /var/piler
create_dir_if_not_exist /var/piler/error
create_dir_if_not_exist /var/piler/imap
create_dir_if_not_exist /var/piler/sphinx
create_dir_if_not_exist /var/piler/stat
create_dir_if_not_exist /var/piler/store
create_dir_if_not_exist /var/piler/tmp
create_dir_if_not_exist /var/run/piler

create_dir_if_not_exist /var/piler/www
create_dir_if_not_exist /var/piler/www/tmp 
create_dir_if_not_exist /var/piler/www/images
echo "run postinst\n"
/bin/bash /piler-postinst

#service rsyslog start

echo "waiting for mysql"
while ! mysqladmin ping -h"$MYSQL_HOSTNAME" --silent; do
    echo -n "."
    sleep 2
done

if [ $(mysql -N -s -h"$MYSQL_HOSTNAME" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE"  -e "select count(*) FROM INFORMATION_SCHEMA.TABLES WHERE table_name='sph_index';") -gt 0 ];
then
    echo "mariadb is well"
    mysql -N -s -h"$MYSQL_HOSTNAME" --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" "$MYSQL_DATABASE"  -e "select count(*) FROM INFORMATION_SCHEMA.TABLES WHERE table_name='sph_index';"
else
    create_mysql_db
fi

pre_seed_sphinx
fix_configs

service cron start
echo "starting php8,1-fpm"
/etc/init.d/php8.1-fpm start
echo "starting nginx"
/etc/init.d/nginx start
echo "starting rc.searchd"
/etc/init.d/rc.searchd start



# fix for overlay, https://github.com/phusion/baseimage-docker/issues/198
touch /var/spool/cron/crontabs/piler

/etc/init.d/rc.piler start

while true; do sleep 120; done
