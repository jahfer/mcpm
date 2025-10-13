require "mods/mods"

class Add < CLI::Kit::BaseCommand
  command_name('add')
  desc('Add a mod to the configuration.')
  long_desc(<<~LONGDESC)
    Adds a mod to the configuration using the specified query.
  LONGDESC
  usage('[dir] --query QUERY')
  example('my-mod', "install a mod named 'my-mod'")

  class Opts < CLI::Kit::Opts
    def dir
      path = option!(long: '--dir', short: '-d', desc: 'Directory containing the MCPM configuration file', default: Dir.pwd)
      File.expand_path(path)
    end

    def query
      option!(name: :query, short: '-q', long: '--query', desc: 'Search query for mods')
    end
  end

  def invoke(op, _name)
    config = mod_config(op.dir)
    query = op.query
    results = Mods::Modrinth.search_projects(
      query,
      limit: 5,
      minecraft_version: config.minecraft_version,
      mod_loader: config.mod_loader
    )

    mod = choose(config, results)
    config.add_mod!(mod)
  end

  private

  def mod_config(dir) = Mods::ModConfig.new(dir)

  def choose(config, results)
    selected_mod = nil

    if results.empty?
      puts "No mods found."
      return
    elsif results.size == 1
      puts "results: #{results.inspect}"
      selected_mod = results.first
      puts CLI::UI.fmt("Found 1 mod: {{bold:#{selected_mod.fetch('title')}}} by #{selected_mod.fetch('author')} {{gray:(#{selected_mod.fetch('downloads')} downloads)}}")
    else
      CLI::UI.ask('Multiple matches found. Select a mod to install') do |handler|
        results.each do |opt|
          description = "{{bold:#{opt.fetch('title')}}} by #{opt.fetch('author')} {{gray:(#{opt.fetch('downloads')} downloads)}}"
          handler.option(description) { selected_mod = opt }
        end
      end
    end

    is_server_side = ['required', 'optional'].include?(selected_mod.fetch('server_side'))
    is_client_side = ['required', 'optional'].include?(selected_mod.fetch('client_side'))
    mod_type = if is_server_side && is_client_side
      'client_and_server'
    elsif is_server_side
      'server_only'
    elsif is_client_side
      'client_only'
    end

    remote_file = Mods::Modrinth.remote_file_for_mod(
      project_id: selected_mod.fetch('project_id'),
      minecraft_version: config.minecraft_version,
      mod_loader: config.mod_loader
    )

    filename_pattern = remote_file.fetch('filename').split(/[0-9]/, 2).first

    Mods::ModDeclaration.new(
      project_id: selected_mod.fetch('project_id'),
      name: selected_mod.fetch('title'),
      type: mod_type,
      filename_pattern: "#{filename_pattern}.*\\.jar$",
      depends_on: [], # TODO
      is_platform: false,
      optional: false
    )
  end
end