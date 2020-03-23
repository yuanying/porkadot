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
      global_config = self.global_config
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

       endpoint = "https://127.0.0.1:#{global_config.k8s.apiserver.bind_port}/healthz"
       info "Start to wait for Bootstrapping Kubernetes API: #{endpoint}"
        while !test('curl', '-skf', endpoint)
          info "Still wating for Bootstrapping Kubernetes API..."
          sleep 5
        end
      end
    end

    def cleanup
      global_config = self.global_config
      config = self.config
      on(host) do |host|
        execute(:mkdir, '-p', Porkadot::Install::KUBE_TEMP)
        if test("[ -d #{KUBE_TEMP} ]")
          execute(:rm, '-rf', KUBE_TEMP)
        end
        upload! config.target_path, KUBE_TEMP, recursive: true

        global_config.nodes.each do |k, node|
          if node.apiserver?
            endpoint = "https://#{node.hostname}:#{global_config.k8s.apiserver.bind_port}/healthz"
            info "Start to wait api node #{node.hostname}"
            while !test('curl', '-skf', endpoint)
              info "Still waiting for API node: #{node.hostname}"
              sleep 5
            end
          end
        end

        endpoint = "https://#{global_config.k8s.control_plane_endpoint}/healthz"
        info "Start to wait api endpoint"
        while !test('curl', '-skf', endpoint)
          info "Still waiting for API: #{endpoint}"
          sleep 5
        end

        as user: 'root' do
          execute(:bash, File.join(KUBE_TEMP, 'cleanup.sh'))
        end
      end
    end

  end

end; end
