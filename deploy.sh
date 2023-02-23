#!/bin/bash

set -v
export HOSTIP=192.168.86.35

export VAULT_ADDR=http://${HOSTIP}:8200

vault operator init -key-shares=1  -key-threshold=1 --format json >> init.txt
export ROOT_TOKEN=$(cat init.txt | jq -r .root_token)
export UNSEAL_KEY=$(cat init.txt | jq -r .unseal_keys_b64[0])

vault operator unseal $UNSEAL_KEY
vault login $ROOT_TOKEN


#Create admin user
echo '
path "*" {
    capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}' | vault policy write vault_admin -
vault auth enable userpass
vault write auth/userpass/users/vault password=vault policies=vault_admin

vault secrets enable -path secret -version=2 kv
vault secrets enable database


vault kv put secret/my-secret username=admin private_key=@./config/openssh/openssh-key
vault kv put secret/my-app-secret username=application-user password=application-password



echo '
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/revoke-self" {
  capabilities = ["update"]
}

path "sys/leases/renew" {
  capabilities = ["update"]
}

path "sys/leases/revoke" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}' | vault policy write boundary-controller -


echo '
path "secret/data/my-secret" {
  capabilities = ["read"]
}

path "secret/data/my-app-secret" {
  capabilities = ["read"]
}' | vault policy write linux-ssh-policy -


export SERVER_CRED_STORE_TOKEN=$(vault token create \
    -no-default-policy=true \
    -policy="vault_admin" \
    -orphan=true \
    -period=20m \
    -renewable=true \
    -format=json | jq -r .auth.client_token)

export ORG_ID=$(boundary scopes create \
 -scope-id=global -name="Docker Lab" \
 -description="Docker Org" \
 -format=json | jq -r '.item.id')


export PROJECT_ID=$(boundary scopes create \
 -scope-id=$ORG_ID -name="Docker Servers" \
 -description="Server Machines" \
 -format=json | jq -r '.item.id')


export SERVER_CRED_STORE_ID=$(boundary credential-stores create vault \
 -name="Vault Server Cred Store" \
 -worker-filter='"dockerworker" in "/tags/type"' \
 -scope-id=$PROJECT_ID \
 -vault-address=$VAULT_ADDR \
 -vault-token=$SERVER_CRED_STORE_TOKEN \
 -format=json | jq -r '.item.id')
 

export SERVER_CRED_LIB_ID=$(boundary credential-libraries create vault \
 -name="Server Cred Library" \
 -credential-store-id $SERVER_CRED_STORE_ID \
 -credential-type ssh_private_key \
 -vault-path "secret/data/my-secret" \
 -format=json | jq -r '.item.id')



export LINUX_TCP_TARGET=$(boundary targets create tcp \
   -name="Linux TCP" \
   -description="Linux server with tcp" \
   -address=$HOSTIP \
   -default-port=2222 \
   -scope-id=$PROJECT_ID \
   -egress-worker-filter='"dockerworker" in "/tags/type"' \
   -format=json | jq -r '.item.id')

export LINUX_SSH_TARGET=$(boundary targets create ssh \
   -name="Linux" \
   -description="Linux server with SSH Injection" \
   -address=$HOSTIP \
   -default-port=2222 \
   -scope-id=$PROJECT_ID \
   -egress-worker-filter='"dockerworker" in "/tags/type"' \
   -format=json | jq -r '.item.id')


boundary targets add-credential-sources \
-id $LINUX_SSH_TARGET \
-injected-application-credential-source $SERVER_CRED_LIB_ID