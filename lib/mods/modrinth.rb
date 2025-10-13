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
        http_get(uri)
      end

      def fetch_versions_response(project_id, minecraft_version: nil, mod_loader: nil)
        uri = URI("#{API_BASE_URL}/project/#{project_id}/version")

        params = {}
        params['game_versions'] = minecraft_version if minecraft_version
        params['loaders'] = mod_loader if mod_loader

        http_get(uri, params)
      end

      private

      def http_get(uri, params = {})
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        uri.query = URI.encode_www_form(params) unless params.empty?

        puts "GET #{uri}" if ENV['MCPM_DEBUG']

        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'mcpm/0.1'
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