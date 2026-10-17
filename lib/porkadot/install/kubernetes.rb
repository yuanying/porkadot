module Porkadot; module Install
  class Kubernetes
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubernetes')
    # Used by porkadot before secrets were merged into the assets tree.
    LEGACY_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.kubernetes')
    KUBECONFIG = File.join(KUBE_TEMP, 'kubeconfig.yaml')
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.kubernetes
      @logger = global_config.logger
    end

    def install host, target=''
      global_config = self.global_config
      config = self.config
      uploader = Porkadot::Install::Uploader.new(global_config)
      on(host) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        execute(:rm, '-rf', KUBE_TEMP, LEGACY_SECRETS_TEMP)
        uploader.upload_tree(self, config.target_path, KUBE_TEMP)

        # as user: 'root' do
        with KUBE_TARGET: target do
          with KUBECONFIG: KUBECONFIG do
            execute(:bash, File.join(KUBE_TEMP, 'install.secrets.sh'))
            # execute(:bash, File.join(KUBE_TEMP, 'install.sh'), interaction_handler: SSHKit::MappingInteractionHandler.new({}, :info))
            info capture(:bash, File.join(KUBE_TEMP, 'install.sh'))
          end
        end
      end
    end

  end

end; end
