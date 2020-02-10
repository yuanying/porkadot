module Porkadot; module Assets
  module Certs

    def certs_root_dir
      File.join(self.config.assets_dir, 'certs')
    end

  end
end; end

require 'porkadot/assets/certs/etcd'
require 'porkadot/assets/certs/k8s'
require 'porkadot/assets/certs/front_proxy'
