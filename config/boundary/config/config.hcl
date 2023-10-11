disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9203"
  purpose = "proxy"
}

worker {
  initial_upstreams = ["8beba06b-04d5-3cba-341a-04ab7f8aef5b.proxy.boundary.hashicorp.cloud:9202"]
  auth_storage_path = "/boundary-hcp-worker/file/dockerlab"
  recording_storage_path = "/boundary-hcp-worker/recording/"
  tags {
    type = ["dockerlab"]
  }
}