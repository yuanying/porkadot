require 'ipaddr'

module Porkadot
  class ConfigValidator
    Error = Class.new(StandardError)

    def initialize(config)
      @config = config
    end

    def validate!
      errors = validate
      raise Error, errors.join("\n") unless errors.empty?
      true
    end

    def validate
      errors = []

      validate_nodes(errors)
      validate_control_plane_endpoint(errors)
      validate_cidrs(errors)
      validate_addons(errors)
      validate_connection(errors)

      errors
    end

    private

    attr_reader :config

    def raw
      config.raw
    end

    def validate_nodes(errors)
      nodes = raw.nodes
      unless nodes.is_a?(Hash)
        errors << 'nodes must be a Hash'
        return
      end

      nodes.each do |name, node|
        next unless node.is_a?(Hash)

        labels = node[:labels] || node['labels']
        next unless labels.is_a?(Hash)
        next unless labels.key?(Porkadot::ETCD_MEMBER_LABEL)

        value = labels[Porkadot::ETCD_MEMBER_LABEL]
        if blank?(value)
          errors << "nodes.#{name}.labels.#{Porkadot::ETCD_MEMBER_LABEL} must not be empty"
        end
      end
    end

    def validate_control_plane_endpoint(errors)
      endpoint = raw.dig(:kubernetes, :control_plane_endpoint)
      if blank?(endpoint)
        errors << 'kubernetes.control_plane_endpoint is required'
        return
      end

      unless endpoint.is_a?(String)
        errors << 'kubernetes.control_plane_endpoint must be a String'
        return
      end

      host, port = split_host_port(endpoint)
      if blank?(host) || blank?(port)
        errors << 'kubernetes.control_plane_endpoint must include host and port'
      end
    end

    def validate_cidrs(errors)
      validate_cidr_list(errors, 'kubernetes.networking.service_subnet',
        raw.dig(:kubernetes, :networking, :service_subnet))
      validate_cidr_list(errors, 'kubernetes.networking.pod_subnet',
        raw.dig(:kubernetes, :networking, :pod_subnet))
    end

    def validate_cidr_list(errors, path, value)
      if blank?(value)
        errors << "#{path} is required"
        return
      end

      unless value.is_a?(String)
        errors << "#{path} must be a String"
        return
      end

      value.split(',').each do |cidr|
        cidr = cidr.strip
        begin
          IPAddr.new(cidr)
        rescue IPAddr::InvalidAddressError
          errors << "#{path} contains invalid CIDR: #{cidr}"
        end
      end
    end

    def validate_addons(errors)
      enabled = raw.dig(:addons, :enabled)
      unless enabled.is_a?(Array)
        errors << 'addons.enabled must be an Array'
        return
      end

      known_addons = Porkadot::Assets::Addons.manifest_names
      enabled.each do |name|
        next if known_addons.include?(name)

        errors << "addons.enabled contains unknown addon: #{name}"
      end
    end

    def validate_connection(errors)
      user = raw.dig(:connection, :user)
      errors << 'connection.user is required' if blank?(user)

      port = raw.dig(:connection, :port)
      unless integerish?(port)
        errors << 'connection.port must be an Integer'
      end
    end

    def split_host_port(endpoint)
      index = endpoint.rindex(':')
      return [nil, nil] unless index

      [endpoint[0, index], endpoint[(index + 1)..-1]]
    end

    def integerish?(value)
      return true if value.is_a?(Integer)
      return false unless value.is_a?(String)

      value.match?(/\A\d+\z/)
    end

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
