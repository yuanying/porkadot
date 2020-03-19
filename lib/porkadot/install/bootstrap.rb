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
      @host = Porkadot::Install::Kubelet.new(self.config.kubelet_config)
    end

    def install
      config = self.config
      on(host) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
        end
        upload! config.target_path, KUBE_TEMP, recursive: true

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end
      end
    end

  end

end; end
