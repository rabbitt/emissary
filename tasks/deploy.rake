require 'rake'
require 'rubygems'

PACKAGE_NAME = 'emissary'

GEM_SERVER_NAME   = 'gems.ec2.nytimes.com'
GEM_SERVER_USER   = 'gem'
GEM_DEPLOY_PATH   = '/opt/nyt/gemrepo/gems'
GEM_SERVER_SSHKEY = '/opt/hudson/.ssh/gem-access.dsa-private'

PKG_PATH = File.join(File.dirname(__FILE__), '..', 'pkg', 'emissary-*.gem')
SSH_USER_HOST_PATH = "#{GEM_SERVER_USER}@#{GEM_SERVER_NAME}:#{GEM_DEPLOY_PATH}"

CURRENT_VERSION = YAML.load(File.read(File.join(File.dirname(__FILE__), '..', 'VERSION.yml'))).values.join '.'

namespace :deploy do
  desc "Builds and deploys the gem"
  task :run => :test do
    puts %x{ rake gem --silent }
    sh "scp -i '#{GEM_SERVER_SSHKEY}' '#{Dir[PKG_PATH].first}' #{SSH_USER_HOST_PATH}"
    puts %x{ rake clean --silent }
  end
  
  desc "test whether or not #{PACKAGE_NAME} can be deployed"
  task :test do
    unless need_to_increment?(PACKAGE_NAME)
      puts "#{PACKAGE_NAME} already deployed at version '#{CURRENT_VERSION}'"
      exit 0
    end
  end
end

def need_to_increment? name
  !current_version_deployed?(name, CURRENT_VERSION)
end


def current_version_deployed?(name, version)

  with_gem_source "http://#{GEM_SERVER_NAME}" do     
    dependency = Gem::Dependency.new(name.to_s, Gem::Requirement.new("= #{version}"))
    list = []
    list |= Gem::SpecFetcher.fetcher.find_matching(dependency, false).map do |spec, source_uri|
      spec[1] # index 1 is the version
    end.sort { |a,b| a[0] <=> b[0] }
  
    return list.empty? ? false : true
  end
end

def with_gem_source new_source
  original_sources = Marshal.load(Marshal.dump(Gem.sources))
  Gem.sources = [ new_source ].flatten
  yield  
ensure
  Gem.sources = original_sources
end
