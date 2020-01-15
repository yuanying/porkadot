module Porkadot; module Assets
  class Kubelet
    attr_reader :config
    attr_reader :logger
  
    def initialize config
      @config = config
      @logger = config.logger
    end

    
  end
end; end
