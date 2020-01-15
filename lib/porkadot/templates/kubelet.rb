module Porkadot; module Templates
  class Kubelet
    attr_reader :config
    attr_reader :logger
    attr_reader :cert_assets

    def initialize config, cert_assets
      @config = config
      @logger = config.logger
      @cert_assets = cert_assets
    end
  end
end; end
