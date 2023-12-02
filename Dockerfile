FROM ubuntu:jammy

LABEL maintainer="bmachek"



# environment settings
ARG DEBIAN_FRONTEND="noninteractive"
ENV MYSQL_HOSTNAME="localhost" \
    MYSQL_DATABASE="piler" \
    MYSQL_PASSWORD="piler123" \
    MYSQL_USER="piler" \
    MYSQL_ROOT_PASSWORD="abcde123" \
    PILER_VERSION="1.4.4" \
    PACKAGE="${PACKAGE:-piler-1.4.4.tar.gz}" 

# must be set in two steps, as in in one the env is still emty
ENV PUID_NAME="${PUID_NAME:-piler}"
ENV PILER_USER="${PUID_NAME}"

ENV BUILD_DIR="${BUILD_DIR:-/BUILD}"
RUN mkdir -p ${BUILD_DIR}

ENV HOME="/var/piler" \
PUID_NAME=${PUID_NAME:-abc} \
PUID=${PUID:-9001} \
PGID=${PGID:-9001}

RUN \
 echo "**** install packages ****" && \
 apt-get update && \
 apt-get install -y \
 nvi wget curl rsyslog openssl sysstat php8.1-cli php8.1-cgi php8.1-mysql php8.1-fpm php8.1-zip php8.1-ldap \
 php8.1-gd php8.1-curl php8.1-xml catdoc unrtf poppler-utils nginx tnef sudo libodbc1 libpq5 libzip4 \
 libtre5 libwrap0 cron libmariadb3 python3 python3-mysqldb php-memcached memcached mariadb-client gpgv1 gpgv2 \
 sphinxsearch libmariadb-dev build-essential \
 libcurl4-openssl-dev php8.1-dev libwrap0-dev libtre-dev libzip-dev libc6 libc6-dev


# need on ubuntu / debian etc
RUN \
 printf "www-data ALL=(root:root) NOPASSWD: /etc/init.d/rc.piler reload\n" > /etc/sudoers.d/81-www-data-sudo-rc-piler-reload && \
 printf "Defaults\\072\\045www-data \\041requiretty\\n" >> /etc/sudoers.d/81-www-data-sudo-rc-piler-reload && \
 chmod 0440 /etc/sudoers.d/81-www-data-sudo-rc-piler-reload

RUN \
    mkdir -p /etc/piler && \
    sed -i 's/^/###/' /etc/init.d/sphinxsearch && \
    echo "### piler install, comment full file to stop the OS reindex" >> /etc/init.d/sphinxsearch && \
    sed -i 's/mail.[iwe].*//' /etc/rsyslog.conf && \
    sed -i '/session    required     pam_loginuid.so/c\#session    required     pam_loginuid.so' /etc/pam.d/cron && \
    # mkdir /etc/piler && \
    printf "[mysql]\nuser = ${MYSQL_USER}\npassword = ${MYSQL_PASSWORD}\n" > /etc/piler/.my.cnf && \
    printf "[mysql]\nuser = root\npassword = ${MYSQL_ROOT_PASSWORD}\n" > /root/.my.cnf && \
    echo "alias mysql='mysql --defaults-file=/etc/piler/.my.cnf'" > /root/.bashrc && \
    echo "alias t='tail -f /var/log/syslog'" >> /root/.bashrc

RUN groupadd --gid $PGID piler
RUN useradd --uid $PUID -g piler -d /var/piler -s /bin/bash piler
RUN usermod -L piler
RUN mkdir /var/piler && chmod 755 /var/piler

RUN \
 echo "**** download tarball ****" && \
 wget "https://bitbucket.org/jsuto/piler/downloads/${PACKAGE}" -O "/${PACKAGE}"

RUN echo "**** install piler package via source tgz ****"  && \
 tar --directory=${BUILD_DIR} --restrict --strip-components=1 -zxvf ${PACKAGE} && \
 rm -f ${PACKAGE}


RUN echo "**** build piler package from source ****"  && \
    cd ${BUILD_DIR} && \
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --with-database=mariadb && \
    make clean all

RUN echo "**** continue with the setup ****" && \
    touch /var/log/mail.log && \
    rm -f /etc/nginx/sites-enabled/default && \
    echo "**** cleanup ****" && \
    apt-get purge --auto-remove -y && \
    apt-get clean

COPY start.sh /start.sh
COPY piler_${PILER_VERSION}-postinst /piler-postinst
COPY piler_${PILER_VERSION}-etc_piler-nginx.conf.dist /piler-nginx.conf.dist

EXPOSE 25 80

VOLUME /etc/piler
VOLUME /var/piler

CMD ["/bin/bash", "/start.sh"]
