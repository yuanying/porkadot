
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

    def target_path
      File.join(self.config.assets_dir, 'kubernetes')
    end

    def manifests_path
      File.join(self.target_path, 'manifests')
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
