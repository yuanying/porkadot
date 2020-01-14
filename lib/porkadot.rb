require 'thor'

require "porkadot/version"

module Porkadot
  class Error < StandardError; end
  # Your code goes here...
end

require 'porkadot/const'
require 'porkadot/config'
require 'porkadot/utils'
require 'porkadot/cli'
