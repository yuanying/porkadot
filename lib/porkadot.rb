require 'thor'
require 'sshkit'
require 'json'

require "porkadot/version"

module Porkadot
  class Error < StandardError; end

  # --node takes a key of nodes in porkadot.yaml. A value that names no node,
  # or a node that cannot run the command, stops the command before it runs
  # anywhere: it must not fall back to what leaving --node out does.
  class NodeError < Error
    def self.unknown name, nodes
      new("Unknown node: #{name}\n--node takes a key of nodes in porkadot.yaml: #{nodes.join(', ')}")
    end

    def self.not_etcd_member name, members
      new("Node is not an etcd member: #{name}\netcd members: #{members.join(', ')}")
    end

    def self.not_control_plane name, masters
      new("Node is not a control plane node: #{name}\n" \
        "Control plane nodes (#{Porkadot::K8S_MASTER_LABEL}): #{masters.join(', ')}")
    end
  end
  # Your code goes here...
end

require 'porkadot/const'
require 'porkadot/utils/hash_recursive_merge'
require 'porkadot/config_validator'
require 'porkadot/config'
require 'porkadot/sops'
require 'porkadot/asset_store'
require 'porkadot/assets'
require 'porkadot/utils'

require 'porkadot/configs/certs'
require 'porkadot/configs/kubelet'
require 'porkadot/configs/kubernetes'
require 'porkadot/configs/etcd'
require 'porkadot/configs/bootstrap'
require 'porkadot/configs/kubernetes'
require 'porkadot/configs/addons'

require 'porkadot/assets/certs'
require 'porkadot/assets/kubelet'
require 'porkadot/assets/etcd'
require 'porkadot/assets/bootstrap'
require 'porkadot/assets/kubernetes'

require 'porkadot/install/base'
require 'porkadot/install/ssh'
require 'porkadot/install/uploader'
require 'porkadot/install/kubelet'
require 'porkadot/install/kubernetes'
require 'porkadot/install/bootstrap'
require 'porkadot/install/rotate_certs'

require 'porkadot/cmd/render/certs'
require 'porkadot/cmd/render'
require 'porkadot/cmd/install/bootstrap'
require 'porkadot/cmd/install/kubernetes'
require 'porkadot/cmd/install'
require 'porkadot/cmd/etcd'
require 'porkadot/cmd/rotate_certs'
require 'porkadot/cmd/migrate_secrets'
require 'porkadot/cmd'
