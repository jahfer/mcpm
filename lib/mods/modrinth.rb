require 'net/http'

require 'mods/minecraft_version'

module Mods
  module Modrinth
    API_BASE_URL = 'https://api.modrinth.com/v2'

    class Error < StandardError; end
    class NotFoundError < Error; end
    class APIError < Error; end

    class << self
      def fetch_project(project_id)
        uri = URI("#{API_BASE_URL}/project/#{project_id}")
        response = http_get(uri)

        case response.code
        when 200
          JSON.parse(response.body.to_s)
        when 404
          raise NotFoundError, "Project with ID #{project_id} not found"
        else
          raise APIError, "Modrinth API error: #{response.code} - #{response.body.to_s}"
        end
      end

      def fetch_supported_versions(project_id, mod_loader: nil)
        @fetch_supported_versions ||= {}
        @fetch_supported_versions["#{project_id}_#{mod_loader}"] ||= fetch_versions(project_id, mod_loader: mod_loader)
      end

      private

      def fetch_versions(project_id, minecraft_version: nil, mod_loader: nil)
        uri = URI("#{API_BASE_URL}/project/#{project_id}/version")

        params = {}
        params['game_versions'] = minecraft_version if minecraft_version
        params['loaders'] = mod_loader if mod_loader

        response = http_get(uri, params)

        case response.code.to_i
        when 200
          versions = JSON.parse(response.body.to_s)
          all_versions = versions.flat_map do |v|
            v['game_versions'].map { |gv| MinecraftVersion.new(gv) }
          end.uniq

          if versions.empty?
            raise NotFoundError, "No versions found for project #{project_id} with specified filters"
          end
          all_versions.select(&:release?).sort
        when 404
          raise NotFoundError, "Project with ID #{project_id} not found"
        else
          raise APIError, "Modrinth API error: #{response.code} - #{response.body.to_s}"
        end
      end

      private

      def http_get(uri, params = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'mcpm/0.1'
        http.request(request)
      end
    end
  end
end