#!/bin/bash

set -v
export HOSTIP=172.16.10.118

docker-compose down
docker-compose down --volumes

export ORG_ID_DEL=$(boundary scopes list -format=json | jq -r '.items[] | select(.name == "Docker Lab") | .id')
export WORKER_DEL=$(boundary workers list -format=json | jq -r '.items[] | select(.type == "pki") | .id')


boundary scopes delete -id=$ORG_ID_DEL


boundary workers delete -id=$WORKER_DEL

kind delete cluster

rm -rf cluster.yaml
rm -rf init.txt
rm -rf ca.crt
rm -rf vault-cluster-role.yaml
rm -rf ./config/boundary/file/* 
rm -rf ./config/vault/file/* 
