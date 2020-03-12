
module Porkadot
  ROOT = File.expand_path("../..", __FILE__)

  K8S_MASTER_LABEL = "node-role.kubernetes.io/master"
  ETCD_MEMBER_LABEL = "etcd.unstable.cloud/member"
  ETCD_ADDRESS_LABEL = "etcd.unstable.cloud/address"
end
