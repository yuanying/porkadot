
module Porkadot
  ROOT = File.expand_path("../..", __FILE__)

  K8S_MASTER_LABEL = "node-role.kubernetes.io/master"
  ETCD_NODE_LABEL = "etcd.unstable.cloud/node"
end
