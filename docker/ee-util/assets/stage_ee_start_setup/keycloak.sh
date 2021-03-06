#!/bin/bash
source keycloak_functions.sh
echo "$T $(date)"

#
# Wait for Login
#
echo -n "$T"
RESPONSE=$($KCADM config credentials --server http://keycloak:8080/keycloak/auth --realm master --user KeycloakAdmin --client admin-cli --password $ADMIN_PASSWORD)
STATUS="$?"
LOOP_COUNT=0
while [ $STATUS != 0 ]; do
    echo "$T Waiting for keycloak [$STATUS] ($RESPONSE) ..."
    sleep 15
    RESPONSE=$($KCADM config credentials --server http://keycloak:8080/keycloak/auth --realm master --user KeycloakAdmin --client admin-cli --password $ADMIN_PASSWORD)
    STATUS="$?"
    ((LOOP_COUNT += 1))
    if [ $LOOP_COUNT -eq 20 ]; then exit -1; fi
done

#
# Assert Elexis-Environment Realm exists
#
REALMID=$($KCADM get realms/ElexisEnvironment --fields id -c --format csv --noquotes)
if [ -z $REALMID ]; then
    echo -n "$T create ElexisEnvironment realm ... "
    $KCADM create realms -s realm=ElexisEnvironment -s enabled=true -s displayName=Elexis-Environment -s sslRequired=none -i
    REALMID=$($KCADM get realms/ElexisEnvironment --fields id -c --format csv --noquotes)
    echo "ok $REALMID"
fi

#
# Update ElexisEnvironment Realm configuration
#
echo "$T Basic ElexisEnvironment realm settings ..."
$KCADM update realms/ElexisEnvironment -s userManagedAccessAllowed=true -s bruteForceProtected=true -s loginTheme=elexis

#
# Provide Elexis-Environment realm keys to other services
#
echo "$T Output realm keys to /ElexisEnvironmentRealmKeys.json ..."
$KCADM get keys -r ElexisEnvironment >/ElexisEnvironmentRealmKeys.json
echo "$T Add realm public key to DB ${RDBMS_ELEXIS_DATABASE}"
REALM_PUBLIC_KEY=$(jq '.keys[] | select(.algorithm == "RS256") | select(.status == "ACTIVE") | .publicKey' -r /ElexisEnvironmentRealmKeys.json)
LASTUPDATE=$(date +%s)000
# Put realm public key into elexis database
MYSQL_STRING="INSERT INTO CONFIG(lastupdate, param, wert) VALUES ('${LASTUPDATE}','EE_KC_REALM_PUBLIC_KEY', '${REALM_PUBLIC_KEY}') ON DUPLICATE KEY UPDATE wert = '${REALM_PUBLIC_KEY}', lastupdate='${LASTUPDATE}'"
/usql mysql://${RDBMS_ELEXIS_USERNAME}:${RDBMS_ELEXIS_PASSWORD}@${RDBMS_HOST}:${RDBMS_PORT}/${RDBMS_ELEXIS_DATABASE} -c "$MYSQL_STRING"

#
# Assert Browser Conditional Otp flow exists and is set as default
#
T="$S (browser dynamic otp flow)"
BROWSER_COND_OTP_FLOW_ID=$($KCADM get authentication/flows -r ElexisEnvironment --format csv --fields id,alias,description --noquotes | grep ,EE\ browser | cut -d "," -f1)
if [ ! -z $BROWSER_COND_OTP_FLOW_ID ]; then
    echo "$T remove existing ... "
    $KCADM update realms/ElexisEnvironment -s browserFlow='browser' # otherwise removal fails
    $KCADM delete authentication/flows/$BROWSER_COND_OTP_FLOW_ID -r ElexisEnvironment
fi

echo "$T create flow ... "
BROWSER_COND_OTP_FLOW_ID=$($KCADM create authentication/flows -r ElexisEnvironment -s alias='EE browser dynamic otp' -s providerId=basic-flow -s description='browser based authentication with conditional otp' -s topLevel=true -i)
EXECUTION_ID=$($KCADM create authentication/flows/EE%20browser%20dynamic%20otp/executions/execution -r ElexisEnvironment -s provider=auth-cookie -i)
$KCADM update authentication/flows/EE%20browser%20dynamic%20otp/executions -r ElexisEnvironment -s id=$EXECUTION_ID -f keycloak/browser_cond_otp_flow_cookie.json
echo "$T create [EE Browser Dynamic Otp Forms] sub flow ..."
SUB_FLOW_ID=$($KCADM create authentication/flows/EE%20browser%20dynamic%20otp/executions/flow -r ElexisEnvironment -s alias='EE Browser Dynamic Otp Forms' -s type='basic-flow' -i)
EXECUTION_ID=$($KCADM get authentication/flows/EE%20browser%20dynamic%20otp/executions -r ElexisEnvironment --format csv --noquotes | grep $SUB_FLOW_ID | cut -d "," -f1)
$KCADM update authentication/flows/EE%20browser%20dynamic%20otp/executions -r ElexisEnvironment -s id=$EXECUTION_ID -s flowId=$SUB_FLOW_ID -f keycloak/browser_cond_otp_flow_subflow.json
EXECUTION_ID=$($KCADM create authentication/flows/EE%20Browser%20Dynamic%20Otp%20Forms/executions/execution -r ElexisEnvironment -s provider=auth-username-password-form -i)
$KCADM update authentication/flows/EE%20browser%20dynamic%20otp/executions -r ElexisEnvironment -s id=$EXECUTION_ID -f keycloak/browser_cond_otp_flow_subflow_userpass.json
EXECUTION_ID=$($KCADM create authentication/flows/EE%20Browser%20Dynamic%20Otp%20Forms/executions/execution -r ElexisEnvironment -s provider=auth-conditional-otp-form -i)
$KCADM update authentication/flows/EE%20browser%20dynamic%20otp/executions -r ElexisEnvironment -s id=$EXECUTION_ID -f keycloak/browser_cond_otp_flow_subflow_condotp.json
$KCADM create authentication/executions/$EXECUTION_ID/config -r ElexisEnvironment -f keycloak/browser_cond_otp_flow_subflow_condotp_config.json
echo "$T setting as default browser flow ..."
$KCADM update realms/ElexisEnvironment -s browserFlow='EE browser dynamic otp'

#
# Assert ldap user storage provider
#
T="$S (ldap-storage-provider)"
LDAP_USP_ID=$($KCADM get components -r ElexisEnvironment --format csv --fields providerId,id,providerType --noquotes | grep org.keycloak.storage.UserStorageProvider\$ | grep ^ldap | cut -d "," -f2)
if [ -z $LDAP_USP_ID ]; then
    echo -n "$T create ldap storage provider ... "
    LDAP_USP_ID=$($KCADM create components -r ElexisEnvironment -s name=ldap -s providerId=ldap -s providerType=org.keycloak.storage.UserStorageProvider -s parentId=$REALMID \
        -s 'config.bindCredential=["'$ADMIN_PASSWORD'"]' -s 'config.bindDn=["'cn=admin,$ORGANISATION_BASE_DN'"]' -s 'config.usersDn=["'ou=people,$ORGANISATION_BASE_DN'"]' -f keycloak/ldap.json -i)
    echo "ok $LDAP_USP_ID"

    echo -n "$T create group-ldap-mapper ... "
    LDAP_UPS_GM_ID=$($KCADM create components -r ElexisEnvironment -s name=ldap_groups -s providerId=group-ldap-mapper -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
        -s parentId=$LDAP_USP_ID -s 'config."groups.dn"=["'ou=groups,$ORGANISATION_BASE_DN'"]' -f keycloak/ldap_groups.json -i)
    echo "ok $LDAP_UPS_GM_ID"

    echo -n "$T create elexisContactId user-attribute-ldap-mapper ..."
    LDAP_UPS_UALM_EC_ID=$($KCADM create components -r ElexisEnvironment -s name=elexisContactId -s providerId=user-attribute-ldap-mapper -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
        -s parentId=$LDAP_USP_ID -s 'config."ldap.attribute"=["elexisContactId"]' -s 'config."user.model.attribute"=["elexisContactId"]' -i)
    echo "ok $LDAP_UPS_UALM_EC_ID"
fi

echo "$T trigger synchronization of all users ... "
$KCADM create -r ElexisEnvironment user-storage/$LDAP_USP_ID/sync?action=triggerFullSync

#
# ROCKETCHAT-SAML
# Re-create on every startup
#
T="$S (rocketchat-saml)"
RC_SAML_CLIENTID=$(getClientId rocketchat-saml\$)
if [ -z $RC_SAML_CLIENTID ]; then
    echo -n "$T create client ... "
    RC_SAML_CLIENTID=$($KCADM create clients -r ElexisEnvironment -s clientId=rocketchat-saml -i)
    echo "ok $RC_SAML_CLIENTID"
fi

echo "$T update client settings ... "
openssl req -nodes -new -x509 -keyout /rocketchat-saml-private.key -out /rocketchat-saml-public.cert -subj "/C=CH/ST=$ORGANISATION_NAME/L=SAML/O=Rocketchat"
RC_SAML_PUBLIC_CERT=$(cat /rocketchat-saml-public.cert | sed '1,1d' | sed '$ d')
$KCADM update clients/$RC_SAML_CLIENTID -r ElexisEnvironment -s 'attributes."saml.signing.certificate"='"$RC_SAML_PUBLIC_CERT" -s adminUrl=https://$EE_HOSTNAME/chat/_saml_metadata/rocketchat-saml -f keycloak/rocketchat-saml.json
# see https://rocket.chat/docs/administrator-guides/permissions/ for full list, only using relevant roles
createOrUpdateClientRole $RC_SAML_CLIENTID user 'description=Normal user rights. Most users receive this role when registering.'
createOrUpdateClientRole $RC_SAML_CLIENTID admin 'description=Have access to all settings and administrator tools.'
createOrUpdateClientRole $RC_SAML_CLIENTID livechat-agent 'description=Agents of livechat. They can answer to livechat requests.'
createOrUpdateClientRole $RC_SAML_CLIENTID livechat-manager 'description=Manager of livechat, they can manage agents and guest.'
echo "$T update client enabled=$ENABLE_ROCKETCHAT"
$KCADM update clients/$RC_SAML_CLIENTID -r ElexisEnvironment -s enabled=$ENABLE_ROCKETCHAT

#
# BOOKSTACK-SAML
#
T="$S (bookstack-saml)"
BS_SAML_CLIENTID=$(getClientId bookstack\/saml2\/metadata)
if [ -z $BS_SAML_CLIENTID ]; then
    echo -n "$T create client ... "
    BS_SAML_CLIENTID=$($KCADM create clients -r ElexisEnvironment -s clientId=https://$EE_HOSTNAME/bookstack/saml2/metadata -i)
    echo "ok $BS_SAML_CLIENTID"
fi

echo "$T update client settings ... "
$KCADM update clients/$BS_SAML_CLIENTID -r ElexisEnvironment -f keycloak/bookstack-saml.json
createOrUpdateClientRole $BS_SAML_CLIENTID admin 'description=Administrator of the whole application'
createOrUpdateClientRole $BS_SAML_CLIENTID editor 'description=User can edit Books, Chapters & Pages'
createOrUpdateClientRole $BS_SAML_CLIENTID viewer 'description=User can view books & their content behind authentication'
createOrUpdateClientRole $BS_SAML_CLIENTID public 'description=The role given to public visitors if allowed'
echo "$T update client enabled=$ENABLE_BOOKSTACK"
$KCADM update clients/$BS_SAML_CLIENTID -r ElexisEnvironment -s enabled=$ENABLE_BOOKSTACK

#
# NEXTCLOUD-SAML
#
T="$S (nexctcloud-saml)"
NC_SAML_CLIENTID=$(getClientId cloud\/apps\/user)
if [ -z $NC_SAML_CLIENTID ]; then
    echo -n "$T create client ... "
    NC_SAML_CLIENTID=$($KCADM create clients -r ElexisEnvironment -s clientId=https://$EE_HOSTNAME/cloud/apps/user_saml/saml/metadata  -i)
    echo "ok $NC_SAML_CLIENTID"
fi

echo "$T update client settings ... "
openssl req -nodes -new -x509 -keyout /nextcloud-saml-private.key -out /nextcloud-saml-public.cert -subj "/C=CH/ST=$ORGANISATION_NAME/L=SAML/O=Nextcloud"
NC_SAML_PUBLIC_CERT=$(cat /nextcloud-saml-public.cert | sed '1,1d' | sed '$ d')
$KCADM update clients/$NC_SAML_CLIENTID -r ElexisEnvironment -s 'attributes."saml.signing.certificate"='"$NC_SAML_PUBLIC_CERT" -f keycloak/nextcloud-saml.json
echo "$T update client enabled=$ENABLE_NEXTCLOUD"
$KCADM update clients/$NC_SAML_CLIENTID -r ElexisEnvironment -s enabled=$ENABLE_NEXTCLOUD

#
# ELEXIS-RCP-OPENID
# Re-create on every startup
#
T="$S (elexis-rcp-openid)"
ERCP_OPENID_CLIENTID=$(getClientId elexis-rcp-openid)
if [ -z $ERCP_OPENID_CLIENTID ]; then
    echo -n "$T create client ... "
    ERCP_OPENID_CLIENTID=$($KCADM create clients -r ElexisEnvironment -s clientId=elexis-rcp-openid -i)
    echo "ok $ERCP_OPENID_CLIENTID"
fi

echo "$T update client settings ... "
RCP_SECRET_UUID=$(uuidgen)
echo "$T secret: $RCP_SECRET_UUID"
$KCADM update clients/$ERCP_OPENID_CLIENTID -s clientAuthenticatorType=client-secret -s secret=$RCP_SECRET_UUID -f keycloak/elexis-rcp-openid.json
LASTUPDATE=$(date +%s)000
MYSQL_STRING="INSERT INTO CONFIG(lastupdate, param, wert) VALUES ('${LASTUPDATE}','EE_RCP_OPENID_SECRET', '${RCP_SECRET_UUID}') ON DUPLICATE KEY UPDATE wert = '${RCP_SECRET_UUID}', lastupdate='${LASTUPDATE}'"
/usql mysql://${RDBMS_ELEXIS_USERNAME}:${RDBMS_ELEXIS_PASSWORD}@${RDBMS_HOST}:${RDBMS_PORT}/${RDBMS_ELEXIS_DATABASE} -c "$MYSQL_STRING"
# $KCADM create clients/$ERCP_OPENID_CLIENTID/roles -r ElexisEnvironment -s name=user -s 'description=Application user, required to log-in'
# $KCADM create clients/$ERCP_OPENID_CLIENTID/roles -r ElexisEnvironment -s name=doctor
# $KCADM create clients/$ERCP_OPENID_CLIENTID/roles -r ElexisEnvironment -s name=executive_doctor
echo "$T update client enabled=$ENABLE_ELEXIS_RCP"
$KCADM update clients/$ERCP_OPENID_CLIENTID -r ElexisEnvironment -s enabled=$ENABLE_ELEXIS_RCP

#
# ELEXIS-RAP-OPENID
# Re-create on every startup
#
#
#
# TODO: Fix HTTP/HTTPS redirectUri Problem
# TODO: Apply registration update logic
#
#
T="$S (elexis-rap-openid)"
ER_OPENID_CLIENTID=$(getClientId elexis-rap-openid | cut -d "," -f1)
if [ ! -z $ER_OPENID_CLIENTID ]; then
    echo "$T remove existing elexis-rap-openid client... "
    $KCADM delete clients/$ER_OPENID_CLIENTID -r ElexisEnvironment
fi

if [[ $ENABLE_ELEXIS_RAP == true ]]; then
    echo -n "$T assert elexis-rap-openid client ... "
    ER_OPENID_CLIENT=$($KCADM create clients -r ElexisEnvironment -s clientId=elexis-rap-openid -s enabled=true -s clientAuthenticatorType=client-secret -s secret=$X_EE_ELEXIS_RAP_CLIENT_SECRET -s 'redirectUris=["http://'$EE_HOSTNAME'/rap/*"]' -f keycloak/elexis-rap-openid.json -i)
    echo "ok $ER_OPENID_CLIENT"
fi
