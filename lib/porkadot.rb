require 'thor'

require "porkadot/version"

module Porkadot
  class Error < StandardError; end
  # Your code goes here...
end

require 'porkadot/utils/hash_recursive_merge'
require 'porkadot/const'
require 'porkadot/config'
require 'porkadot/utils'
require 'porkadot/cli'
