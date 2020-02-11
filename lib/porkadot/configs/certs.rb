module Porkadot; module Configs
  module Certs

    def certs_root_dir
      File.join(self.config.assets_dir, 'certs')
    end

  end
end; end

require 'porkadot/configs/certs/etcd'
require 'porkadot/configs/certs/k8s'
require 'porkadot/configs/certs/front_proxy'
