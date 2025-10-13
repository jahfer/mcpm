MinecraftVersion = Data.define(:version_number) do
  class << self 
    def latest_version_supported(*lists)
      return nil if lists.empty?
      return lists.first.max if lists.size == 1
      
      lists.reduce do |common, list|
        common.flat_map { |v1| list.select { |v2| v1 == v2 } }.uniq
      end.max.normalized
    end
  end

  def <=>(other)
    self_parts = normalized.version_number.split('.').map(&:to_i)
    other_parts = other.normalized.version_number.split('.').map(&:to_i)

    self_parts <=> other_parts
  end
  
  include Comparable
  
  def release?
    return false if version_number.nil? || version_number.empty?

    # Pattern for stable release versions: major.minor or major.minor.patch
    release_pattern = /\A\d+\.\d+(\.\d+)?\z/
    
    # If it matches the release pattern and doesn't contain experimental keywords
    version_number.match?(release_pattern) &&
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
end

PATCHFIX_VERSIONS = {
  MinecraftVersion['1.21.9'] => MinecraftVersion['1.21.10'],
}.freeze