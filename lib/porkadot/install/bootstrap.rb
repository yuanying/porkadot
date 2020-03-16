module Porkadot; module Install
  class Bootstrap
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'bootstrap')
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger
    attr_reader :host

    def initialize global_config
      @global_config = global_config
      @config = global_config.bootstrap
      @logger = global_config.logger
      @host = KubeletList.new(global_config)[config.node.name]
    end

    def install
      config = self.config
      on(host) do |host|
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
        end
        upload! config.bootstrap_path, KUBE_TEMP, recursive: true

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end
      end
    end

  end

end; end
