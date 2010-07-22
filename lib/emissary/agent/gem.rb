#   Copyright 2010 The New York Times
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
#
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
