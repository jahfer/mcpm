require 'net/http'
require 'digest'
require 'fileutils'

module Mods
  module Downloader
    Error = Class.new(StandardError)
    DownloadError = Class.new(Error)
    ChecksumError = Class.new(Error)

    class << self
      def download_file(url, destination_path)
        uri = URI(url)
        temp_path = "#{destination_path}.tmp"

        begin
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            request = Net::HTTP::Get.new(uri)
            request['User-Agent'] = 'mcpm/0.1'

            http.request(request) do |response|
              unless response.is_a?(Net::HTTPSuccess)
                raise DownloadError, "HTTP error downloading #{File.basename(destination_path)}: #{response.code} #{response.message}"
              end

              File.open(temp_path, 'wb') do |file|
                response.read_body do |chunk|
                  file.write(chunk)
                end
              end
            end
          end

          # Verify the downloaded file is not empty
          unless File.size(temp_path) > 0
            raise DownloadError, "Downloaded file is empty: #{File.basename(destination_path)}"
          end

          # Move temp file to final location
          FileUtils.mv(temp_path, destination_path)

        rescue => e
          # Clean up temp file if it exists
          File.delete(temp_path) if File.exist?(temp_path)
          raise DownloadError, "Download failed for #{File.basename(destination_path)}: #{e.message}"
        end
      end

      def verify_checksum(file_path, expected_sha512, mod_name)
        unless File.exist?(file_path)
          raise ChecksumError, "File does not exist for checksum verification: #{file_path}"
        end

        actual_sha512 = Digest::SHA512.file(file_path).hexdigest
        
        unless actual_sha512 == expected_sha512
          # Clean up the invalid file
          File.delete(file_path) if File.exist?(file_path)
          raise ChecksumError, "Checksum verification failed for mod #{mod_name}. Expected: #{expected_sha512}, got: #{actual_sha512}"
        end
      end
    end
  end
end