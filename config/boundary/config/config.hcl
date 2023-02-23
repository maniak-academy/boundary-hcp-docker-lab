disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9203"
  purpose = "proxy"
}

worker {
  initial_upstreams = ["c4059953-5ba0-7db9-5ef9-b5b3b16885e2.proxy.boundary.hashicorp.cloud:9202"]
  auth_storage_path = "/boundary-hcp-worker/file/dockerworker"
  tags {
    type = ["dockerworker", "downstream"]
  }
}