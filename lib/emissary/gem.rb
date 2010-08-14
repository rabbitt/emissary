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
require 'rubygems/spec_fetcher'
require 'rubygems/dependency_installer'
require 'rubygems/uninstaller'

module Emissary
  class GemHelper
    attr_reader :name, :version
    
    def initialize(name)
      @name    = name
      @version = current_version
    end
    
    def normalize_version version
      case version
        when Gem::Requirement, Gem::Version
          version
        
        when /^(<|<=|=|!=|>|>=|~>)\s*[0-9.]+$/
          Gem::Requirement.new version
        when /^[0-9.]+$/, String, Fixnum
          Gem::Version.new version
        
        when :current
          @version || Gem::Version.new('0')
          
        when :all, :any, :installed, :available
          Gem::Requirement.default
        
        when :newer_than_me, :latest, :newest
          Gem::Requirement.new "> #{@version || 0}"
        
        when :older_than_me
          Gem::Requirement.new "< #{@version || 0}"
      end
    end
  
    def updateable?
      installed? && !versions(:newer_than_me).empty?
    end
    
    def is_a_provider? version = :current
      return false unless (spec = Gem.source_index.find_name(@name, normalize_version(version)).first)
      !Gem::DependencyList.from_source_index(Gem.source_index).ok_to_remove?(spec.full_name)
    end
    alias :have_dependents? :is_a_provider?
    alias :has_dependents?  :is_a_provider? 
    
    def removeable? version = :current, ignore_dependents = false
      installed?(version) && (!!ignore_dependents || !have_dependents?(version))
    end
    
    def installable? version = :any
      !versions(:any).empty? && !installed?(version) && @version < normalize_version(version)
    end
    
    def installed? version = :any
      !Gem.source_index.search(Gem::Dependency.new(name, normalize_version(version))).empty?
    end
    
    def current_version
      return Gem::Version.new(0) unless installed?
      specs = Gem.source_index.search(Gem::Dependency.new(name, normalize_version(:newest)))
      specs.map { |spec| spec.version }.sort{ |a,b| a <=> b }.reverse.first
    end
    
    def versions which = :all
      # don't include others for latest/newest - do include otherwise
      others = [:latest, :newest ].include?(which) ? false : true
      dependency = Gem::Dependency.new(name, normalize_version(which))
      list = Gem::SpecFetcher.fetcher.find_matching(dependency, others).map do |spec, source_uri|
        _, version = spec
        [version, source_uri]
      end.sort { |a,b| a[0] <=> b[0] }
      
      which != :installed ? list : list.select { |v| installed? v[0]  } 
    end
  
    def dependents version = :current
      specs = Gem.source_index.find_name(@name, normalize_version(version))
      specs.inject([]) do |list,spec|
        list |= spec.dependent_gems
        list
      end
    end
  
    def install version = :latest, source = :default
      return @version unless installable? version
      
      source = URI.parse(source).to_s rescue :default
      
      options = {}
      options[:version], source_uri = case version
        when :latest
          ver, uri = versions(:newer_than_me).first
          [ ver, source == :default ? uri : source ]
        else
          ver, uri = versions(:newer_than_me).select { |v| v[0] == normalize_version(version) }.flatten
          [ ver, source == :default ? uri : source ]
      end
          
      raise ArgumentError, "Bad version '#{version.inspect}' - can't install specified version." unless options[:version]
  
      # only use the specified source (whether default or user specified)
      begin
        original_sources = Gem.sources.dup
        Gem.sources.replace [source_uri]
        
        installer = Gem::DependencyInstaller.new options
    
        installer.install name, options[:version]
        @version = normalize_version options[:version]
      ensure
        Gem.sources.replace original_sources
        Gem.refresh
      end
      
      true
    end
  
    def update version = :latest, source = :default, keep_old = true
      return false unless updateable?
      uninstall(@version, false) unless keep_old
      install version, source 
  
      @version = normalize_version version
    end
    
    def uninstall version = :current, ignore_deps = false, remove_execs = false
      options = {}
      options[:ignore] = !!ignore_deps
      options[:executables] = !!remove_execs
  
      options[:version] = case version
        when :current
          @version
        when :all
          options[:all] = true
          Gem::Requirement.default
        else
          versions(:all).select { |v| v[0] == normalize_version(version) }.flatten[0]
      end
  
      return true if not installed? version 
      raise ArgumentError, "Cannot uninstall version #{version.inspect} - is it installed? [#{options.inspect}]" unless options[:version]
  
      unless removeable?(version, !!ignore_deps)
        msg = ['Refusing to uninstall gem required by other gems:']
        dependents(options[:version]).each do |gem, dep, satlist|
          msg << "    Gem '#{gem.name}-#{gem.version}' depends on '#{dep.name}' (#{dep.requirement})";
        end
        raise Exception, msg.join("\n")
      end
  
      Gem::Uninstaller.new(name, options).uninstall
      Gem.refresh 
      @version = Gem::Version.new '0'
    end
    alias :remove :uninstall
  end

end
