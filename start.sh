#!/bin/bash

set -v
export HOSTIP=192.168.86.250

## Setuo K8s using Kind server 

cat > cluster.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
  apiServerAddress: ${HOSTIP}
nodes:
- role: control-plane
  image: kindest/node:v1.23.0
EOF

kind create cluster --config=cluster.yaml


./deploy.sh