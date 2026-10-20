module Porkadot; module Install
  class Kubernetes
    KUBE_TEMP = File.join(Porkadot::Install::KUBE_TEMP, 'kubernetes')
    # Used by porkadot before secrets were merged into the assets tree.
    LEGACY_SECRETS_TEMP = File.join(Porkadot::Install::KUBE_TEMP, '.kubernetes')
    KUBECONFIG = File.join(KUBE_TEMP, 'kubeconfig.yaml')
    DEFAULT_APISERVER_TIMEOUT = 600
    include SSHKit::DSL
    attr_reader :global_config
    attr_reader :config
    attr_reader :logger

    def initialize global_config
      @global_config = global_config
      @config = global_config.kubernetes
      @logger = global_config.logger
    end

    # Unless a single target is given, install.sh applies the kube-apiserver
    # first and waits up to apiserver_timeout seconds for its rollout before
    # applying the rest. wait_apiserver: false applies everything at once.
    def install host, target='', wait_apiserver: true, apiserver_timeout: DEFAULT_APISERVER_TIMEOUT
      global_config = self.global_config
      config = self.config
      uploader = Porkadot::Install::Uploader.new(global_config)
      on(host) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        execute(:rm, '-rf', KUBE_TEMP, LEGACY_SECRETS_TEMP)
        uploader.upload_tree(self, config.target_path, KUBE_TEMP)

        # as user: 'root' do
        with KUBE_TARGET: target, KUBE_WAIT_APISERVER: wait_apiserver.to_s, KUBE_APISERVER_TIMEOUT: apiserver_timeout.to_i.to_s do
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
