require 'thor'

require "porkadot/version"

module Porkadot
  class Error < StandardError; end
  # Your code goes here...
end

require 'porkadot/const'
require 'porkadot/utils/hash_recursive_merge'
require 'porkadot/config'
require 'porkadot/utils'

require 'porkadot/assets/certs'
require 'porkadot/assets/kubelet'

require 'porkadot/templates/certs'
require 'porkadot/templates/kubelet'

require 'porkadot/cmd/render/certs'
require 'porkadot/cmd/render'
require 'porkadot/cmd'
