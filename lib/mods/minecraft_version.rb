MinecraftVersion = Data.define(:version_number) do
  def <=>(other)
    self_parts = version_number.split('.').map(&:to_i)
    other_parts = other.version_number.split('.').map(&:to_i)

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
end