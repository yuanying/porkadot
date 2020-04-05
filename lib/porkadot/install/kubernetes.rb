module Porkadot; module Install
  class Kubernetes
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubernetes')
    KUBE_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.kubernetes')
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.kubernetes
      @logger = global_config.logger
    end

    def install host
      # global_config = self.global_config
      config = self.config
      on(host) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
          execute(:rm, '-rf', KUBE_SECRETS_TEMP)
        end
        upload! config.target_path, KUBE_TEMP, recursive: true
        upload! config.target_secrets_path, KUBE_SECRETS_TEMP, recursive: true
        execute(:cp, '-r', KUBE_SECRETS_TEMP + '/*', KUBE_TEMP)

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'install.sh'))
        end
      end
    end

  end

end; end
