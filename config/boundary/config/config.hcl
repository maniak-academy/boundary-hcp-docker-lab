disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9203"
  purpose = "proxy"
}

worker {
  initial_upstreams = ["ed0f098d-862a-6742-ca9e-666b5d4f9664.proxy.boundary.hashicorp.cloud:9202"]
  auth_storage_path = "/boundary-hcp-worker/file/dockerlab"
  tags {
    type = ["dockerlab"]
  }
}