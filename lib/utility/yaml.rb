require 'yaml'

module Utility
  module YAML

    class << self
      def load_file(filepath)
        content = File.read(filepath)
        ::YAML.safe_load(content) || {}
      rescue Psych::SyntaxError => e
        raise "YAML syntax error in file #{filepath}: #{e.message}"
      end

      def dump_to_file(data, filepath:, format: true)
        yaml_content = ::YAML.dump(data)
        yaml_content = format_yaml(yaml_content) if format
        File.write(filepath, yaml_content)
      rescue => e
        raise "Failed to write YAML to file #{filepath}: #{e.message}"
      end

      private

      def format_yaml(yaml_content)
        yaml_content.gsub("\n-", "\n\n-")
      rescue => e
        raise "Failed to format YAML content: #{e.message}"
      end
    end
  end
end