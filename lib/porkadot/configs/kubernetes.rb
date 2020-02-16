
module Porkadot; module Configs
  class Kubernetes
    include Porkadot::ConfigUtils
    attr_reader :config
    attr_reader :logger
    attr_reader :raw
    attr_reader :networking

    def initialize config
      @config = config
      @logger = config.logger
      @raw = config.raw.kubernetes

      @networking = Networking.new(config)
    end

    class Networking
      include Porkadot::ConfigUtils
      attr_reader :config
      attr_reader :logger
      attr_reader :raw

      def initialize config
        @config = config
        @logger = config.logger
        @raw = config.raw.kubernetes.networking
      end

      def dns_ip
        cluster_ip_range = IPAddr.new(self.service_subnet)
        cluster_ip_range.to_range.first(11)[10].to_s
      end
    end
  end
end; end
