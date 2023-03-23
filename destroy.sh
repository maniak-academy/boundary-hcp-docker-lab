#!/bin/bash

set -v
export HOSTIP=192.168.86.250

docker-compose down

kind delete cluster