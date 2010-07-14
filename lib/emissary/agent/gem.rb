require 'emissary/agent'
require 'emissary/gem'

module Emissary
  class Agent::Gem < Agent
    def valid_methods
      [ :update, :install, :remove, :uninstall ]
    end

    # Updates Emissary from the given source to the given version
    def install gem_name, version = :latest, source_url = :default
      ::Emissary::Gem.new(gem_name).install(version, source_url)
    end
    
    def update gem_name, version = :latest, source_url = :default
      ::Emissary::Gem.new(gem_name).update(version, source_url)
    end
    
    def uninstall gem_name, version = :latest, ignore_dependencies = true, remove_executables = false
      ::Emissary::Gem.new(gem_name).uninstall(version, ignore_dependencies, remove_executables)
    end
    alias :remove :uninstall    
  end

end
