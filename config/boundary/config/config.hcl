disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9203"
  purpose = "proxy"
}

worker {
  initial_upstreams = ["29078e00-5749-b7ba-c2a5-f11a47769ece.proxy.boundary.hashicorp.cloud:9202"]
  auth_storage_path = "/boundary-hcp-worker/file/dockerlab"
  tags {
    type = ["dockerlab"]
  }
}