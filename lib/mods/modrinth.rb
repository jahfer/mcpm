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

      def fetch_supported_versions(project_id, minecraft_version: nil, mod_loader: nil)
        @fetch_supported_versions ||= {}
        @fetch_supported_versions["#{project_id}_#{mod_loader}"] ||= begin
          versions = fetch_versions_response(project_id, minecraft_version: minecraft_version, mod_loader: mod_loader)
          all_versions = versions.flat_map do |v|
            v['game_versions'].map { |gv| MinecraftVersion.new(gv) }
          end.uniq

          if versions.empty?
            raise NotFoundError, "No versions found for project #{project_id} with specified filters"
          end
          all_versions.select(&:release?).sort
        end
      end

      def remote_file_for_mod(project_id:, minecraft_version: nil, mod_loader: nil)
        available_version = fetch_versions_response(project_id, minecraft_version:, mod_loader:).first
        response = fetch_version_response(available_version.fetch("id"))
        response.fetch("files", []).first
      end

      private

      def fetch_version_response(version_id)
        uri = URI("#{API_BASE_URL}/version/#{version_id}")
        response = http_get(uri)

        case response.code.to_i
        when 200
          JSON.parse(response.body.to_s)
        when 404
          raise NotFoundError, "Version with ID #{version_id} not found"
        else
          raise APIError, "Modrinth API error: #{response.code} - #{response.body.to_s}"
        end
      end

      def fetch_versions_response(project_id, minecraft_version: nil, mod_loader: nil)
        @version_response_cache ||= {}
        cache_key = "#{project_id}_#{minecraft_version}_#{mod_loader}"

        response = @version_response_cache[cache_key] ||= begin
          uri = URI("#{API_BASE_URL}/project/#{project_id}/version")

          params = {}
          params['game_versions'] = minecraft_version if minecraft_version
          params['loaders'] = mod_loader if mod_loader

          response = http_get(uri, params)
        end

        case response.code.to_i
        when 200
          JSON.parse(response.body.to_s)
        when 404
          raise NotFoundError, "Project with ID #{project_id} not found"
        else
          @version_response_cache.delete(cache_key)
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