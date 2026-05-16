require 'net/http'

require 'mods/minecraft_version'

module Mods
  module Modrinth
    API_BASE_URL = 'https://api.modrinth.com/v2'

    class Error < StandardError; end
    class NotFoundError < Error; end
    class APIError < Error; end

    class << self
      def search_projects(query, limit: 10, minecraft_version:, mod_loader:)
        uri = URI("#{API_BASE_URL}/search")
        filters = {
          project_type: "mod",
          categories: mod_loader,
          versions: minecraft_version
        }

        facets = JSON.generate(filters.map { |k, v| Array("#{k}:#{v}") })
        params = { query:, limit:, facets: }
        
        response = http_get(uri, params)
        response.fetch("hits", [])
      end

      def fetch_project(project_id)
        uri = URI("#{API_BASE_URL}/project/#{project_id}")
        http_get(uri)
      end

      def fetch_supported_versions(project_id, minecraft_version: nil, mod_loader: nil)
        @fetch_supported_versions ||= {}
        cache_key = [project_id, minecraft_version&.to_s, mod_loader].join('_')

        @fetch_supported_versions[cache_key] ||= begin
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

      def fetch_available_versions(project_id, minecraft_version: nil, mod_loader: nil)
        compatible_versions_response(project_id, minecraft_version:, mod_loader:).map do |v|
          VersionInfo.new(v.fetch("version_number"), MinecraftVersion.new(v.fetch("game_versions").first))
        end
      end

      def remote_file_for_mod(project_id:, minecraft_version: nil, mod_loader: nil)
        selected_version = compatible_versions_response(project_id, minecraft_version:, mod_loader:).first
        raise NotFoundError, "No versions found for project #{project_id} with specified filters" unless selected_version

        response = fetch_version_response(selected_version.fetch("id"))
        response.fetch("files", []).first
      end

      private

      def fetch_version_response(version_id)
        uri = URI("#{API_BASE_URL}/version/#{version_id}")
        http_get(uri)
      end

      def fetch_versions_response(project_id, minecraft_version: nil, mod_loader: nil)
        uri = URI("#{API_BASE_URL}/project/#{project_id}/version")

        params = {}
        params['game_versions'] = JSON.generate([minecraft_version.to_s]) if minecraft_version
        params['loaders'] = JSON.generate([mod_loader]) if mod_loader

        http_get(uri, params)
      end

      def compatible_versions_response(project_id, minecraft_version: nil, mod_loader: nil)
        versions = fetch_versions_response(project_id, minecraft_version:, mod_loader:)
        return versions if versions.any? || minecraft_version.nil?

        fetch_versions_response(project_id, mod_loader:).select do |version|
          version.fetch('game_versions', []).any? do |game_version|
            MinecraftVersion.new(game_version).compatible_with?(minecraft_version)
          end
        end
      end

      private

      def http_get(uri, params = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        uri.query = URI.encode_www_form(params) unless params.empty?

        puts "GET #{uri}" if ENV['MCPM_DEBUG']

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'jahfer/mcpm/0.1'
        response = http.request(request)

        case response.code.to_i
        when 200
          JSON.parse(response.body)
        when 404
          raise NotFoundError, "Resource not found at #{uri}"
        when 429
          raise APIError, "Rate limited by Modrinth API"
        else
          raise APIError, "Modrinth API error: #{response.code} - #{response.body.to_s}"
        end
      end
    end
  end
end
