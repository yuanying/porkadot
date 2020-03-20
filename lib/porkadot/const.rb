
module Porkadot
  ROOT = File.expand_path("../..", __FILE__)

  K8S_MASTER_LABEL = "k8s.unstable.cloud/master"
  ETCD_MEMBER_LABEL = "etcd.unstable.cloud/member"
  ETCD_ADDRESS_LABEL = "etcd.unstable.cloud/address"
end
