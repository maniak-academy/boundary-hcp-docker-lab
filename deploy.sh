#!/bin/bash

set -v
export HOSTIP=192.168.86.250

## Setuo K8s using Kind server 

cat > ./config/kind/cluster.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
  apiServerAddress: ${HOSTIP}
nodes:
- role: control-plane
  image: kindest/node:v1.23.0
EOF

kind create cluster --config=./config/kind/cluster.yaml


cat > ./config/kind/vault-cluster-role.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault
  namespace: vault
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: k8s-full-secrets-abilities-with-labels
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["serviceaccounts", "serviceaccounts/token"]
  verbs: ["create", "update", "delete"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["rolebindings", "clusterrolebindings"]
  verbs: ["create", "update", "delete"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "clusterroles"]
  verbs: ["bind", "escalate", "create", "update", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-creator-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: k8s-full-secrets-abilities-with-labels
subjects:
- kind: ServiceAccount
  name: vault
  namespace: vault
EOF


kubectl create namespace vault
kubectl apply -f ./config/kind/vault-cluster-role.yaml

### DEPLOY VAULT 

export VAULT_ADDR=http://${HOSTIP}:8200

vault operator init -key-shares=1  -key-threshold=1 --format json >> init.txt
export ROOT_TOKEN=$(cat init.txt | jq -r .root_token)
export UNSEAL_KEY=$(cat init.txt | jq -r .unseal_keys_b64[0])

vault operator unseal $UNSEAL_KEY
vault login $ROOT_TOKEN



export VAULT_SVC_ACCT_TOKEN="$(kubectl get secret -n vault `kubectl get serviceaccounts vault -n vault -o jsonpath='{.secrets[0].name}'` -o jsonpath='{.data.token}' | base64 -d)" 

export KUBE_API_URL=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"$(kubectl config current-context)\")].cluster.server}")

kubectl config view --minify --raw --output 'jsonpath={..cluster.certificate-authority-data}' | base64 -d > ca.crt


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


vault secrets enable kubernetes
vault secrets enable -path=k8s-secret kv-v2
vault kv put k8s-secret/k8s-cluster ca_crt=@ca.crt

vault write -f kubernetes/config \
  kubernetes_host=$KUBE_API_URL \
  kubernetes_ca_cert=@ca.crt \
  service_account_jwt=$VAULT_SVC_ACCT_TOKEN

vault write kubernetes/roles/auto-managed-sa-and-role \
allowed_kubernetes_namespaces="*" \
token_default_ttl="10m" \
generated_role_rules='{"rules":[{"apiGroups":[""],"resources":["pods"],"verbs":["list"]}]}'


### DEPLOY VAULT POLICIES

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


echo '
path "database/creds/dba" {
  capabilities = ["read"]
}' | vault policy write docker-db-policy -


#K8s policy

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
}
 
path "kubernetes/creds/auto-managed-sa-and-role" {
  capabilities = ["update"]
}

path "k8-secret/data/k8s-cluster" {
 capabilities = ["read"]
}' | vault policy write k8s-policy -


export K8S_CRED_STORE_TOKEN=$(vault token create \
    -no-default-policy=true \
    -policy="k8s-policy" \
    -orphan=true \
    -period=20m \
    -renewable=true \
    -format=json | jq -r .auth.client_token)

export SERVER_CRED_STORE_TOKEN=$(vault token create \
    -no-default-policy=true \
    -policy="vault_admin" \
    -policy="boundary-controller" \
    -policy="linux-ssh-policy" \
    -orphan=true \
    -period=20m \
    -renewable=true \
    -format=json | jq -r .auth.client_token)

export DB_CRED_STORE_TOKEN=$(vault token create \
    -no-default-policy=true \
    -policy="boundary-controller" \
    -policy="docker-db-policy" \
    -orphan=true \
    -period=20m \
    -renewable=true \
    -format=json | jq -r .auth.client_token)

### DEPLOY BOUNDARY ORGS AND PROJECTS


export ORG_ID=$(boundary scopes create \
 -scope-id=global -name="Docker Lab" \
 -description="Docker Org" \
 -format=json | jq -r '.item.id')


export PROJECT_ID=$(boundary scopes create \
 -scope-id=$ORG_ID -name="Docker Servers" \
 -description="Server Machines" \
 -format=json | jq -r '.item.id')


export DB_PROJECT_ID=$(boundary scopes create \
 -scope-id=$ORG_ID -name="Docker DB" \
 -description="DB Infra" \
 -format=json | jq -r '.item.id')


export K8S_PROJECT_ID=$(boundary scopes create \
 -scope-id=$ORG_ID -name="Docker K8s" \
 -description="K8s Infra" \
 -format=json | jq -r '.item.id')

### DEPLOY CREDENTIAL STORE AND LIBRARY


export SERVER_CRED_STORE_ID=$(boundary credential-stores create vault \
 -name="Vault Server Cred Store" \
 -worker-filter='"dockerlab" in "/tags/type"' \
 -scope-id=$PROJECT_ID \
 -vault-address=$VAULT_ADDR \
 -vault-token=$SERVER_CRED_STORE_TOKEN \
 -format=json | jq -r '.item.id')

export DB_CRED_STORE_ID=$(boundary credential-stores create vault \
 -name="Vault DB Cred Store" \
 -worker-filter='"dockerlab" in "/tags/type"' \
 -scope-id=$DB_PROJECT_ID \
 -vault-address=$VAULT_ADDR \
 -vault-token=$DB_CRED_STORE_TOKEN \
 -format=json | jq -r '.item.id')


export SERVER_CRED_LIB_ID=$(boundary credential-libraries create vault \
 -name="Server Cred Library" \
 -credential-store-id $SERVER_CRED_STORE_ID \
 -credential-type ssh_private_key \
 -vault-path "secret/data/my-secret" \
 -format=json | jq -r '.item.id')

export K8S_CRED_STORE_ID=$(boundary credential-stores create vault \
 -name="Vault K8s Cred Store" \
 -worker-filter='"dockerlab" in "/tags/type"' \
 -scope-id=$K8S_PROJECT_ID \
 -vault-address=$VAULT_ADDR \
 -vault-token=$K8S_CRED_STORE_TOKEN \
 -format=json | jq -r '.item.id')


export K8S_CRED_LIB_ID=$(boundary credential-libraries create vault \
 -name="K8S Cred Library" \
 -credential-store-id $K8S_CRED_STORE_ID \
 -vault-path "kubernetes/creds/auto-managed-sa-and-role" \
 -vault-http-method=post \
 -vault-http-request-body='{"kubernetes_namespace": "default"}' \
 -format=json | jq -r '.item.id')


export K8S_SECRET_CRED_LIB_ID=$(boundary credential-libraries create vault \
 -name="K8S Secret Cred Library" \
 -credential-store-id $K8S_CRED_STORE_ID \
 -vault-path "k8s-secret/data/k8s-cluster" \
 -vault-http-method=GET \
 -format=json | jq -r '.item.id')

### DEPLOY TARGETS

export LINUX_TCP_TARGET=$(boundary targets create tcp \
   -name="Linux TCP" \
   -description="Linux server with tcp" \
   -address=$HOSTIP \
   -default-port=2222 \
   -scope-id=$PROJECT_ID \
   -egress-worker-filter='"dockerlab" in "/tags/type"' \
   -format=json | jq -r '.item.id')

export LINUX_SSH_TARGET=$(boundary targets create ssh \
   -name="Linux" \
   -description="Linux server with SSH Injection" \
   -address=$HOSTIP \
   -default-port=2222 \
   -scope-id=$PROJECT_ID \
   -egress-worker-filter='"dockerlab" in "/tags/type"' \
   -format=json | jq -r '.item.id')

export K8S_TARGET=$(boundary targets create tcp \
   -name="K8S TCP" \
   -description="K8S server with tcp" \
   -address=$HOSTIP \
   -default-port="59103" \
   -scope-id=$K8S_PROJECT_ID \
   -egress-worker-filter='"dockerlab" in "/tags/type"' \
   -format=json | jq -r '.item.id')


boundary targets add-credential-sources \
-id $K8S_TARGET \
-brokered-credential-source=$K8S_SECRET_CRED_LIB_ID 

boundary targets add-credential-sources \
-id $K8S_TARGET \
-brokered-credential-source=$K8S_CRED_LIB_ID


boundary targets add-credential-sources \
-id $LINUX_SSH_TARGET \
-injected-application-credential-source $SERVER_CRED_LIB_ID

export PG_DB="database";export PG_URL="postgres://postgres:secret@${HOSTIP}:5432/${database}?sslmode=disable"


vault write database/config/database \
      plugin_name=postgresql-database-plugin \
      connection_url="postgresql://{{username}}:{{password}}@${HOSTIP}:5432/database?sslmode=disable" \
      allowed_roles=dba \
      username="admin" \
      password="dbroot"



vault write database/roles/dba \
    db_name=database \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    ALTER USER \"{{name}}\" WITH SUPERUSER;" \
    default_ttl="1h" \
    max_ttl="24h"


export DB_CRED_LIB_ID=$(boundary credential-libraries create vault \
    -name="DB Cred Library" \
    -credential-store-id $DB_CRED_STORE_ID \
    -credential-type username_password \
    -vault-path "database/creds/dba" \
    -format=json | jq -r '.item.id')

export DB_TARGET=$(boundary targets create tcp \
   -name="Postgres DB" \
   -description="Postgres DB brokering with Vault" \
   -address=$HOSTIP \
   -default-port=5432 \
   -scope-id=$DB_PROJECT_ID \
   -egress-worker-filter='"dockerlab" in "/tags/type"' \
   -format=json | jq -r '.item.id')

boundary targets add-credential-sources \
  -id=$DB_TARGET \
  -application-credential-source=$DB_CRED_LIB_ID

kubectl config view -o jsonpath="{.clusters[?(@.name == \"$(kubectl config current-context)\")].cluster.server}"
