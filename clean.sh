# ------------------------------------------
# This script cleans extra files from /arc
# to keep the layers as small as possible.
# ------------------------------------------

# Stop on error
set -e
# Treat unset variables and parameters as an error.
set -u

# Strip all the unneeded symbols from shared libraries to reduce size.
find /arc -type f -name "*.so*" -exec strip --strip-unneeded {} \;
find /arc -type f -name "*.a"|xargs rm
find /arc -type f -name "*.la"|xargs rm
find /arc -type f -name "*.dist"|xargs rm
find /arc -type f -executable -exec sh -c "file -i '{}' | grep -q 'x-executable; charset=binary'" \; -print|xargs strip --strip-all

# Cleanup all the binaries we don't want.
find /arc/bin -mindepth 1 -maxdepth 1 ! -name "php" -exec rm {} \+
find /arc/bin -mindepth 1 -maxdepth 1 ! -name "php" -exec rm {} \+

# Cleanup all the files we don't want either
# We do not support running pear functions in Lambda
rm -rf /arc/lib/php/PEAR
rm -rf /arc/share
rm -rf /arc/include
rm -rf /arc/php
rm -rf /arc/{lib,lib64}/pkgconfig
rm -rf /arc/{lib,lib64}/cmake
rm -rf /arc/lib/xml2Conf.sh
find /arc/lib/php -mindepth 1 -maxdepth 1 -type d -a -not -name extensions |xargs rm -rf
find /arc/lib/php -mindepth 1 -maxdepth 1 -type f |xargs rm -rf
rm -rf /arc/lib/php/test
rm -rf /arc/lib/php/doc
rm -rf /arc/lib/php/docs
rm -rf /arc/tests
rm -rf /arc/doc
rm -rf /arc/docs
rm -rf /arc/man
rm -rf /arc/php/man
rm -rf /arc/www
rm -rf /arc/cfg
rm -rf /arc/libexec
rm -rf /arc/var
rm -rf /arc/data
