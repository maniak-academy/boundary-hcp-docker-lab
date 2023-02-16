# Setup Hashicorp HCP Boundary Docker



```
touch docker-compose.yml
mkdir -p volume/{config,file,logs}
```

Populate the boundary hcp config vault.json. (As you can see the config is local)

```
cat > volumes/config/config.hcl << EOF
disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9203"
  purpose = "proxy"
}

worker {
  initial_upstreams = ["ed0f098d-862a-6742-ca9e-666b5d4f9664.proxy.boundary.hashicorp.cloud:9202"]
  auth_storage_path = "/boundary-hcp-worker/file/worker2"
  tags {
    type = ["worker2", "downstream"]
  }
}

EOF
```

Populate the docker-compose.yml:

```
cat > docker-compose.yml << EOF
version: '2'
services:
  boundary-hcp-worker:
    image: hashicorp/boundary-worker-hcp
    container_name: boundary-hcp-worker
    ports:
      - "9203:9203"
      - "9202:9202"
    restart: always
    volumes:
      - ./volume/config:/boundary-hcp-worker/config
      - ./volume/logs:/boundary-hcp-worker/logs
      - ./volume/file:/boundary-hcp-worker/file
    cap_add:
      - IPC_LOCK
    entrypoint: boundary-worker server -config=/boundary-hcp-worker/config/config.hcl
EOF
```