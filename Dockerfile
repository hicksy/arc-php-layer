#Lambda base image Amazon linux
FROM public.ecr.aws/lambda/provided:al2 as builder 

# The container we build here contains everything needed to compile PHP.

# Move to /tmp to compile everything in there.
WORKDIR /tmp


# Lambda is based on Amazon Linux 2. Lock YUM to that release version.
RUN sed -i 's/releasever=latest/releaserver=amzn2/' /etc/yum.conf


RUN set -xe \
    # Download yum repository data to cache
 && yum makecache \
    # Default Development Tools
 && yum groupinstall -y "Development Tools" --setopt=group_package_types=mandatory,default


# The default version of cmake we can get from the yum repo is 2.8.12. We need cmake to build a few of
# our libraries, and at least one library requires a version of cmake greater than that.
#
# Needed to build:
# - libzip: minimum required CMAKE version 3.0.
RUN LD_LIBRARY_PATH= yum install -y cmake3
RUN ln -s /usr/bin/cmake3 /usr/bin/cmake

# Use the bash shell, instead of /bin/sh
# Why? We need to document this.
SHELL ["/bin/bash", "-c"]

# We need a base path for all the sourcecode we will build from.
ENV BUILD_DIR="/tmp/build"

# We need a base path for the builds to install to. This path must
# match the path that bref will be unpackaged to in Lambda.
ENV INSTALL_DIR="/arc"

# Apply stack smash protection to functions using local buffers and alloca()
# ## # Enable size optimization (-Os)
# # Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# # Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)

# We need some default compiler variables setup
ENV PKG_CONFIG_PATH="${INSTALL_DIR}/lib64/pkgconfig:${INSTALL_DIR}/lib/pkgconfig" \
    PKG_CONFIG="/usr/bin/pkg-config" \
    PATH="${INSTALL_DIR}/bin:${PATH}"


ENV LD_LIBRARY_PATH="${INSTALL_DIR}/lib64:${INSTALL_DIR}/lib"

# Enable parallelism for cmake (like make -j)
# See https://stackoverflow.com/a/50883540/245552
RUN export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc)

# Ensure we have all the directories we require in the container.
RUN mkdir -p ${BUILD_DIR}  \
    ${INSTALL_DIR}/bin \
    ${INSTALL_DIR}/doc \
    ${INSTALL_DIR}/etc/php \
    ${INSTALL_DIR}/etc/php/conf.d \
    ${INSTALL_DIR}/include \
    ${INSTALL_DIR}/lib \
    ${INSTALL_DIR}/lib64 \
    ${INSTALL_DIR}/libexec \
    ${INSTALL_DIR}/sbin \
    ${INSTALL_DIR}/share



# Install some dev files for using old libraries already on the system
# readline-devel : needed for the --with-libedit flag
# gettext-devel : needed for the --with-gettext flag
# libicu-devel : needed for
# libxslt-devel : needed for the XSL extension
# sqlite-devel : Since PHP 7.4 this must be installed (https://github.com/php/php-src/blob/99b8e67615159fc600a615e1e97f2d1cf18f14cb/UPGRADING#L616-L619)
RUN LD_LIBRARY_PATH= yum install -y readline-devel gettext-devel libicu-devel libxslt-devel sqlite-devel ncurses-libs 

# MH - added these, based on CW log errors listing various missing libs (ncurses-libs ncurses-libs ncurses-compat-libs)

RUN cp -a /usr/lib64/libncurses.so* ${INSTALL_DIR}/lib64/
RUN cp -a /usr/lib64/libtinfo.so* ${INSTALL_DIR}/lib64/
# MH - end

RUN cp -a /usr/lib64/libgcrypt.so* ${INSTALL_DIR}/lib64/

# Copy readline shared libs that are not present in amazonlinux2
RUN cp -a /usr/lib64/libreadline.so?* ${INSTALL_DIR}/lib64/

# Copy gpg-error shared libds that are not present in amazonlinux2
RUN cp -a /usr/lib64/libgpg-error.so* ${INSTALL_DIR}/lib64/

# Copy gettext shared libs that are not present in amazonlinux2
RUN cp -a /usr/lib64/libasprintf.so* ${INSTALL_DIR}/lib64/
RUN cp -a /usr/lib64/libgettextpo.so* ${INSTALL_DIR}/lib64/
RUN cp -a /usr/lib64/preloadable_libintl.so* ${INSTALL_DIR}/lib64/

# Copy xslt shared libs that are not present in amazonlinux2
RUN cp -a /usr/lib64/lib*xslt*.so* ${INSTALL_DIR}/lib64/

# Copy sqlite3 shared libs that are not present in amazonlinux2
RUN cp -a /usr/lib64/libsqlite3*.so* ${INSTALL_DIR}/lib64/





###############################################################################
# ZLIB Build
# https://github.com/madler/zlib/releases
# Needed for:
#   - openssl
#   - curl
#   - php
# Used By:
#   - xml2
ENV VERSION_ZLIB=1.2.11
ENV ZLIB_BUILD_DIR=${BUILD_DIR}/xml2

RUN set -xe; \
    mkdir -p ${ZLIB_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls  http://zlib.net/zlib-${VERSION_ZLIB}.tar.xz \
  | tar xJC ${ZLIB_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${ZLIB_BUILD_DIR}/

# Configure the build
RUN set -xe; \
    make distclean \
 && CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --prefix=${INSTALL_DIR} \
    --64

RUN set -xe; \
    make install \
 && rm ${INSTALL_DIR}/lib/libz.a

###############################################################################
# OPENSSL Build
# https://github.com/openssl/openssl/releases
# Needs:
#   - zlib
# Needed by:
#   - curl
#   - php
ENV VERSION_OPENSSL=1.1.1k
ENV OPENSSL_BUILD_DIR=${BUILD_DIR}/openssl
ENV CA_BUNDLE_SOURCE="https://curl.se/ca/cacert.pem"
ENV CA_BUNDLE="${INSTALL_DIR}/ssl/cert.pem"


RUN set -xe; \
    mkdir -p ${OPENSSL_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls  https://github.com/openssl/openssl/archive/OpenSSL_${VERSION_OPENSSL//./_}.tar.gz \
  | tar xzC ${OPENSSL_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${OPENSSL_BUILD_DIR}/


# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./config \
        --prefix=${INSTALL_DIR} \
        --openssldir=${INSTALL_DIR}/ssl \
        --release \
        no-tests \
        shared \
        zlib

RUN set -xe; \
    make install \
 && curl -Lk -o ${CA_BUNDLE} ${CA_BUNDLE_SOURCE}

###############################################################################
# LIBSSH2 Build
# https://github.com/libssh2/libssh2/releases
# Needs:
#   - zlib
#   - OpenSSL
# Needed by:
#   - curl
ENV VERSION_LIBSSH2=1.8.2
ENV LIBSSH2_BUILD_DIR=${BUILD_DIR}/libssh2

RUN set -xe; \
    mkdir -p ${LIBSSH2_BUILD_DIR}/bin; \
    # Download and upack the source code
    curl -Ls https://github.com/libssh2/libssh2/releases/download/libssh2-${VERSION_LIBSSH2}/libssh2-${VERSION_LIBSSH2}.tar.gz \
  | tar xzC ${LIBSSH2_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${LIBSSH2_BUILD_DIR}/bin/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    cmake .. \
    -DBUILD_SHARED_LIBS=ON \
    -DCRYPTO_BACKEND=OpenSSL \
    -DENABLE_ZLIB_COMPRESSION=ON \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DCMAKE_BUILD_TYPE=RELEASE

RUN set -xe; \
    cmake  --build . --target install

###############################################################################
# LIBNGHTTP2 Build
# This adds support for HTTP 2 requests in curl.
# See https://github.com/brefphp/bref/issues/727 and https://github.com/brefphp/bref/pull/740
# https://github.com/nghttp2/nghttp2/releases
# Needs:
#   - zlib
#   - OpenSSL
# Needed by:
#   - curl
ENV VERSION_NGHTTP2=1.43.0
ENV NGHTTP2_BUILD_DIR=${BUILD_DIR}/nghttp2

RUN set -xe; \
    mkdir -p ${NGHTTP2_BUILD_DIR}; \
    curl -Ls https://github.com/nghttp2/nghttp2/releases/download/v${VERSION_NGHTTP2}/nghttp2-${VERSION_NGHTTP2}.tar.gz \
    | tar xzC ${NGHTTP2_BUILD_DIR} --strip-components=1

WORKDIR  ${NGHTTP2_BUILD_DIR}/

RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --enable-lib-only \
    --prefix=${INSTALL_DIR}

RUN set -xe; \
    make install


###############################################################################
# CURL Build
# # https://github.com/curl/curl/releases
# # Needs:
# #   - zlib
# #   - OpenSSL
# #   - libssh2
# # Needed by:
# #   - php
ENV VERSION_CURL=7.76.0
ENV CURL_BUILD_DIR=${BUILD_DIR}/curl

RUN set -xe; \
            mkdir -p ${CURL_BUILD_DIR}/bin; \
curl -Ls https://github.com/curl/curl/archive/curl-${VERSION_CURL//./_}.tar.gz \
| tar xzC ${CURL_BUILD_DIR} --strip-components=1


WORKDIR  ${CURL_BUILD_DIR}/

RUN set -xe; \
    ./buildconf \
 && CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --prefix=${INSTALL_DIR} \
    --with-ca-bundle=${CA_BUNDLE} \
    --enable-shared \
    --disable-static \
    --enable-optimize \
    --disable-warnings \
    --disable-dependency-tracking \
    --with-zlib \
    --enable-http \
    --enable-ftp  \
    --enable-file \
    --enable-ldap \
    --enable-ldaps  \
    --enable-proxy  \
    --enable-tftp \
    --enable-ipv6 \
    --enable-openssl-auto-load-config \
    --enable-cookies \
    --with-gnu-ld \
    --with-ssl \
    --with-libssh2 \
    --with-nghttp2


RUN set -xe; \
    make install

###############################################################################
# LIBXML2 Build
# https://github.com/GNOME/libxml2/releases
# Uses:
#   - zlib
# Needed by:
#   - php
ENV VERSION_XML2=2.9.10
ENV XML2_BUILD_DIR=${BUILD_DIR}/xml2

RUN set -xe; \
    mkdir -p ${XML2_BUILD_DIR}; \
# Download and upack the source code
    curl -Ls http://xmlsoft.org/sources/libxml2-${VERSION_XML2}.tar.gz \
  | tar xzC ${XML2_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${XML2_BUILD_DIR}/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure \
    --prefix=${INSTALL_DIR} \
    --with-sysroot=${INSTALL_DIR} \
    --enable-shared \
    --disable-static \
    --with-html \
    --with-history \
    --enable-ipv6=no \
    --with-icu \
    --with-zlib=${INSTALL_DIR} \
    --without-python

RUN set -xe; \
    make install \
 && cp xml2-config ${INSTALL_DIR}/bin/xml2-config

###############################################################################
# LIBZIP Build
# https://github.com/nih-at/libzip/releases
# Needed by:
#   - php
ENV VERSION_ZIP=1.7.3
ENV ZIP_BUILD_DIR=${BUILD_DIR}/zip

RUN set -xe; \
    mkdir -p ${ZIP_BUILD_DIR}/bin/; \
# Download and upack the source code
    curl -Ls https://github.com/nih-at/libzip/releases/download/v${VERSION_ZIP}/libzip-${VERSION_ZIP}.tar.gz \
  | tar xzC ${ZIP_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${ZIP_BUILD_DIR}/bin/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    cmake .. \
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR} \
    -DCMAKE_BUILD_TYPE=RELEASE

RUN set -xe; \
    cmake  --build . --target install

###############################################################################
# LIBSODIUM Build
# https://github.com/jedisct1/libsodium/releases
# Needs:
#
# Needed by:
#   - php
ENV VERSION_LIBSODIUM=1.0.18
ENV LIBSODIUM_BUILD_DIR=${BUILD_DIR}/libsodium

RUN set -xe; \
    mkdir -p ${LIBSODIUM_BUILD_DIR}; \
   # Download and unpack the source code
    curl -Ls https://github.com/jedisct1/libsodium/archive/${VERSION_LIBSODIUM}.tar.gz \
  | tar xzC ${LIBSODIUM_BUILD_DIR} --strip-components=1

# Move into the unpackaged code directory
WORKDIR  ${LIBSODIUM_BUILD_DIR}/

# Configure the build
RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./autogen.sh \
&& ./configure --prefix=${INSTALL_DIR}

RUN set -xe; \
    make install

###############################################################################
# Postgres Build
# https://github.com/postgres/postgres/releases
# Needs:
#   - OpenSSL
# Needed by:
#   - php
ENV VERSION_POSTGRES=9.6.21
ENV POSTGRES_BUILD_DIR=${BUILD_DIR}/postgres

RUN set -xe; \
    mkdir -p ${POSTGRES_BUILD_DIR}/bin; \
    curl -Ls https://github.com/postgres/postgres/archive/REL${VERSION_POSTGRES//./_}.tar.gz \
    | tar xzC ${POSTGRES_BUILD_DIR} --strip-components=1


WORKDIR  ${POSTGRES_BUILD_DIR}/

RUN set -xe; \
    CFLAGS="" \
    CPPFLAGS="-I${INSTALL_DIR}/include  -I/usr/include" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib" \
    ./configure --prefix=${INSTALL_DIR} --with-openssl --without-readline

RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/interfaces/libpq && make -j $(nproc) && make install
RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/bin/pg_config && make -j $(nproc) && make install
RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/backend && make generated-headers
RUN set -xe; cd ${POSTGRES_BUILD_DIR}/src/include && make install



###############################################################################
# Oniguruma
# This library is not packaged in PHP since PHP 7.4.
# See https://github.com/php/php-src/blob/43dc7da8e3719d3e89bd8ec15ebb13f997bbbaa9/UPGRADING#L578-L581
# We do not install the system version because I didn't manage to make it work...
# Ideally we shouldn't compile it ourselves.
# https://github.com/kkos/oniguruma/releases
# Needed by:
#   - php mbstring
ENV VERSION_ONIG=6.9.6
ENV ONIG_BUILD_DIR=${BUILD_DIR}/oniguruma
RUN set -xe; \
    mkdir -p ${ONIG_BUILD_DIR}; \
    curl -Ls https://github.com/kkos/oniguruma/releases/download/v${VERSION_ONIG}/onig-${VERSION_ONIG}.tar.gz \
    | tar xzC ${ONIG_BUILD_DIR} --strip-components=1
WORKDIR  ${ONIG_BUILD_DIR}/
RUN set -xe; \
    ./configure --prefix=${INSTALL_DIR}; \
    make -j $(nproc); \
    make install


ENV VERSION_PHP=7.4.23


ENV PHP_BUILD_DIR=${BUILD_DIR}/php
RUN set -xe; \
    mkdir -p ${PHP_BUILD_DIR}; \
    # Download and upack the source code
    # --location will follow redirects
    # --silent will hide the progress, but also the errors: we restore error messages with --show-error
    # --fail makes sure that curl returns an error instead of fetching the 404 page
    curl --location --silent --show-error --fail https://www.php.net/get/php-${VERSION_PHP}.tar.gz/from/this/mirror \
  | tar xzC ${PHP_BUILD_DIR} --strip-components=1
# Move into the unpackaged code directory
WORKDIR  ${PHP_BUILD_DIR}/

# Configure the build
# -fstack-protector-strong : Be paranoid about stack overflows
# -fpic : Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# -fpie : Support Address Space Layout Randomization (see -fpic)
# -O3 : Optimize for fastest binaries possible.
# -I : Add the path to the list of directories to be searched for header files during preprocessing.
# --enable-option-checking=fatal: make sure invalid --configure-flags are fatal errors instead of just warnings
# --enable-ftp: because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
# --enable-mbstring: because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
# --with-zlib and --with-zlib-dir: See https://stackoverflow.com/a/42978649/245552
# --with-pear: necessary for `pecl` to work (to install PHP extensions)
#
RUN set -xe \
 && ./buildconf --force \
 && CFLAGS="-fstack-protector-strong -fpic -fpie -O3 -I${INSTALL_DIR}/include -I/usr/include -ffunction-sections -fdata-sections" \
    CPPFLAGS="-fstack-protector-strong -fpic -fpie -O3 -I${INSTALL_DIR}/include -I/usr/include -ffunction-sections -fdata-sections" \
    LDFLAGS="-L${INSTALL_DIR}/lib64 -L${INSTALL_DIR}/lib -Wl,-O1 -Wl,--strip-all -Wl,--hash-style=both -pie" \
    ./configure \
        --build=x86_64-pc-linux-gnu \
        --prefix=${INSTALL_DIR} \
        --enable-option-checking=fatal \
        --enable-sockets \
        --with-config-file-path=${INSTALL_DIR}/etc/php \
        --with-config-file-scan-dir=${INSTALL_DIR}/etc/php/conf.d:/var/task/php/conf.d \
        --enable-fpm \
        --disable-cgi \
        --enable-cli \
        --disable-phpdbg \
        --disable-phpdbg-webhelper \
        --with-sodium \
        --with-readline \
        --with-openssl \
        --with-zlib=${INSTALL_DIR} \
        --with-zlib-dir=${INSTALL_DIR} \
        --with-curl \
        --enable-exif \
        --enable-ftp \
        --with-gettext \
        --enable-mbstring \
        --with-pdo-mysql=shared,mysqlnd \
        --with-mysqli \
        --enable-pcntl \
        --with-zip \
        --enable-bcmath \
        --with-pdo-pgsql=shared,${INSTALL_DIR} \
        --enable-intl=shared \
        --enable-soap \
        --with-xsl=${INSTALL_DIR} \
        --with-pear
RUN make -j $(nproc)
# Run `make install` and override PEAR's PHAR URL because pear.php.net is down
RUN set -xe; \
 make install PEAR_INSTALLER_URL='https://github.com/pear/pearweb_phars/raw/master/install-pear-nozlib.phar'; \
 { find ${INSTALL_DIR}/bin ${INSTALL_DIR}/sbin -type f -perm +0111 -exec strip --strip-all '{}' + || true; }; \
 make clean; \
 cp php.ini-production ${INSTALL_DIR}/etc/php/php.ini

# Symlink all our binaries into /opt/bin so that Lambda sees them in the path.
# RUN mkdir -p /opt/bin \
#     && cd /opt/bin \
#     && ln -s ../bin/* . \
#     && ln -s ../sbin/* .

# Install extensions
# We can install extensions manually or using `pecl`
RUN pecl install APCu

RUN curl -sS https://getcomposer.org/installer | ${INSTALL_DIR}/bin/php -- --install-dir=${INSTALL_DIR}/bin/ --filename=composer

# Install Guzzle, prepare vendor files
RUN cd ${INSTALL_DIR} && \
    ${INSTALL_DIR}/bin/php ${INSTALL_DIR}/bin/composer require guzzlehttp/guzzle aws/aws-sdk-php


COPY clean.sh /tmp/clean.sh
RUN chmod +x /tmp/clean.sh
RUN /tmp/clean.sh && rm /tmp/clean.sh

WORKDIR /var/task

COPY runtime/bootstrap ./bootstrap
COPY runtime/runtime.php ${INSTALL_DIR}/runtime.php

RUN chmod 755 ./bootstrap
RUN chmod +x ./bootstrap

RUN zip -qq -y -r runtime.zip bootstrap ${INSTALL_DIR}/ 

FROM scratch as artifact
COPY --from=builder /var/task/runtime.zip /runtime.zip