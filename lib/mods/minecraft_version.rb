class MinecraftVersion
  include Comparable

  class << self
    def [](version_number)
      new(version_number)
    end

    def compatible_version(version)
      return nil unless version

      PATCHFIX_VERSIONS[version] || PATCHFIX_VERSIONS.key(version) || version.compatibility_fallback
    end

    def latest_version_supported(*lists)
      return nil if lists.empty?

      version_lists = lists.map(&:uniq)
      common_compatibility_versions = version_lists
        .map { |list| list.map(&:compatibility_version).uniq }
        .reduce { |common, list| common & list }

      return nil if common_compatibility_versions.nil? || common_compatibility_versions.empty?

      latest_compatibility_version = common_compatibility_versions.max
      matching_versions = version_lists
        .flatten
        .select { |version| version.compatibility_version == latest_compatibility_version }

      ([latest_compatibility_version] + matching_versions).max
    end
  end

  attr_reader :version_number

  def initialize(version_number)
    @version_number = version_number.to_s
    @scheme = parse_scheme(@version_number)
  end

  def ==(other)
    other.is_a?(MinecraftVersion) && version_number == other.version_number
  end
  alias eql? ==

  def hash
    version_number.hash
  end

  def <=>(other)
    return nil unless other.is_a?(MinecraftVersion)

    sort_key <=> other.sort_key
  end

  def release?
    return false if version_number.empty?

    version_number.match?(RELEASE_PATTERN) &&
      !version_number.include?('experimental') &&
      !version_number.include?('snapshot') &&
      !version_number.include?('pre') &&
      !version_number.include?('rc')
  end

  def to_s
    version_number
  end

  def normalized
    PATCHFIX_VERSIONS.fetch(self, self)
  end

  def patchfixed?
    PATCHFIX_VERSIONS.key?(self)
  end

  def compatibility_version
    @compatibility_version ||= @scheme.compatibility_version(self)
  end

  def compatible_with?(other)
    compatibility_version == other.compatibility_version
  end

  def compatibility_fallback
    @scheme.compatibility_fallback(self)
  end

  def year_based?
    @scheme.is_a?(YearBasedScheme)
  end

  def legacy?
    @scheme.is_a?(LegacyScheme)
  end

  protected

  attr_reader :scheme

  def sort_key
    @scheme.sort_key
  end

  private

  RELEASE_PATTERN = /\A\d+\.\d+(\.\d+)?\z/
  YEAR_BASED_PATTERN = /\A(?<year>\d{2})\.(?<drop>\d+)(?:\.(?<hotfix>\d+))?\z/
  LEGACY_PATTERN = /\A(?<major>\d+)\.(?<minor>\d+)(?:\.(?<patch>\d+))?\z/

  def parse_scheme(version_number)
    if (match = version_number.match(YEAR_BASED_PATTERN)) && match[:year].to_i >= 26
      YearBasedScheme.new(match)
    elsif (match = version_number.match(LEGACY_PATTERN))
      LegacyScheme.new(match)
    else
      UnknownScheme.new(version_number)
    end
  end

  class LegacyScheme
    def initialize(match)
      @major = match[:major].to_i
      @minor = match[:minor].to_i
      @patch = match[:patch]&.to_i || 0
    end

    def sort_key
      [0, @major, @minor, @patch]
    end

    def compatibility_version(version)
      PATCHFIX_VERSIONS.fetch(version, version)
    end

    def compatibility_fallback(version)
      PATCHFIX_VERSIONS[version] || PATCHFIX_VERSIONS.key(version)
    end
  end

  class YearBasedScheme
    def initialize(match)
      @year = match[:year].to_i
      @drop = match[:drop].to_i
      @hotfix = match[:hotfix]&.to_i || 0
    end

    def sort_key
      [1, @year, @drop, @hotfix]
    end

    def compatibility_version(_version)
      MinecraftVersion["#{@year}.#{@drop}"]
    end

    def compatibility_fallback(version)
      compatibility_version(version) == version ? nil : compatibility_version(version)
    end
  end

  class UnknownScheme
    def initialize(version_number)
      @version_number = version_number
    end

    def sort_key
      [-1, @version_number]
    end

    def compatibility_version(version)
      version
    end

    def compatibility_fallback(_version)
      nil
    end
  end
end

PATCHFIX_VERSIONS = {
  MinecraftVersion['1.21.9'] => MinecraftVersion['1.21.10'],
}.freeze
