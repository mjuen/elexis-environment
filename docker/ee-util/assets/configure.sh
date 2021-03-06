#!/bin/bash

#
# ASSERT ENVIRONMENT-VARIABLES
#
NOW=$(date +%s)
cp -p /installdir/.env /installdir/.env.bkup.$NOW
mv /installdir/.env /installdir/.env.bkup
java -jar /EnvSubst.jar -s /installdir/.env.bkup -t /installdir/.env.template -f /installdir/.env -i EE_VERSION

#
# REPLACING UUID TEMPLATE VARIABLES
#
sed -i -e "s/=missing-uuid/=$(uuidgen)/g" /installdir/.env

#
# TEST PRECONDITIONS
#
echo "=== Testing environment variables"

bats /stage_configure/tests.bats
if [ $? -ne 0 ]
then
  echo "Tests showed an error, not performing configuration"
  exit -1
fi

#
# PERFORM CONFIGURATION
#
echo "=== Preparing configuration files"

if [ ! -f "/site/dhparam.pem" ]; 
then
    echo "* generating dhparam.pem ... please wait ..."
    openssl dhparam -dsaparam -out /site/dhparam.pem 4096
else
    echo "  skipping dhparam.pem generation"
fi

if [ ! -f "/site/myserver.cnf" ]; 
then
echo "* writing ssl configuration file ..."
cat <<EOF >/site/myserver.cnf
# see https://www.switch.ch/pki/manage/request/csr-openssl/
FQDN=${EE_HOSTNAME}
ORGNAME=${ORGANISATION_NAME}
ALTNAMES = DNS:\$FQDN
[ req ]
default_bits = 2048
default_md = sha256
prompt = no
encrypt_key = no
distinguished_name = dn
req_extensions = req_ext
[ dn ]
C = CH
O = \$ORGNAME
CN = \$FQDN
[ req_ext ]
subjectAltName = \$ALTNAMES
EOF
else
  echo "  skipping myserver.cnf generation"
fi

if [ ! -f "/site/myserver.csr" ]; 
then
    echo "* generating myserver.key/csr"
    openssl req -new -config /site/myserver.cnf -keyout /site/myserver.key -out /site/myserver.csr
else
    echo "  skipping myserver.key/csr generation"
fi

if [ ! -f "/site/bootstrap.ldif" ]; 
then
    echo "* generating bootstrap.ldif"
    SALT="$(openssl rand 3)"
    SHA1="$(printf "%s%s" "$ADMIN_PASSWORD" "$SALT" | openssl dgst -binary -sha1)"
    SHA1_ADMIN_PASS="$(printf "%s%s" "$SHA1" "$SALT" | base64)"
    export SHA1_ADMIN_PASS
    cat /assets/ldap/bootstrap.ldif.template | envsubst > /site/bootstrap.ldif
else
    echo "  skipping ldap/bootstrap.ldif generation"
fi