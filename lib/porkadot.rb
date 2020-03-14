require 'thor'
require 'sshkit'

require "porkadot/version"

module Porkadot
  class Error < StandardError; end
  # Your code goes here...
end

require 'porkadot/const'
require 'porkadot/utils/hash_recursive_merge'
require 'porkadot/config'
require 'porkadot/utils'

require 'porkadot/configs/certs'
require 'porkadot/configs/kubelet'
require 'porkadot/configs/kubernetes'
require 'porkadot/configs/etcd'
require 'porkadot/configs/bootstrap'

require 'porkadot/assets/certs'
require 'porkadot/assets/kubelet'
require 'porkadot/assets/etcd'
require 'porkadot/assets/bootstrap'

require 'porkadot/install/kubelet'

require 'porkadot/cmd/render/certs'
require 'porkadot/cmd/render'
require 'porkadot/cmd/install'
require 'porkadot/cmd'
