
module Porkadot; module Configs
  class Kubernetes
    include Porkadot::ConfigUtils
    attr_reader :config
    attr_reader :logger
    attr_reader :raw

    def initialize config
      @config = config
      @logger = config.logger
      @raw = config.raw.kubernetes
    end

    class Networking
      include Porkadot::ConfigUtils
      attr_reader :config
      attr_reader :logger
      attr_reader :raw

      def initialize config
        @config = config
        @logger = config.logger
        @raw = config.kubernetes.raw.networking
      end
    end
  end
end; end
