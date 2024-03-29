require 'thor'
require 'sshkit'
require 'json'

require "porkadot/version"

module Porkadot
  class Error < StandardError; end
  # Your code goes here...
end

require 'porkadot/const'
require 'porkadot/utils/hash_recursive_merge'
require 'porkadot/config'
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
require 'porkadot/install/kubelet'
require 'porkadot/install/kubernetes'
require 'porkadot/install/bootstrap'

require 'porkadot/cmd/render/certs'
require 'porkadot/cmd/render'
require 'porkadot/cmd/install/bootstrap'
require 'porkadot/cmd/install'
require 'porkadot/cmd/etcd'
require 'porkadot/cmd'
