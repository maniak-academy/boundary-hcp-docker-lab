#!/bin/bash

set -v
export HOSTIP=192.168.86.250

docker-compose down
docker-compose down --volumes

kind delete cluster

rm -rf cluster.yaml
rm -rf init.txt
rm -rf ca.crt
rm -rf vault-cluster-role.yaml
rm -rf ./config/boundary/file/* 
rm -rf ./config/vault/file/* 
