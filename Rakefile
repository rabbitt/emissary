# -*- ruby -*-

require 'rubygems'
require 'find'

def manifest_files
  manifest_files = [];
  base_path    = File.expand_path('.')
  search_paths = [
    File.join(base_path, 'lib'),
    File.join(base_path, 'etc'),
    File.join(base_path, 'bin'),
    File.join(base_path, 'VERSION.yml'),
    File.join(base_path, 'LICENSE'),
  ]
  
  Find.find(*search_paths) do |path|
    if File.directory? path
      File.basename(path)[/^\./] ? Find.prune : next
    end
    manifest_files << path.gsub(base_path + ::File::SEPARATOR, '')
  end
  
  manifest_files
end

GEM         = 'emissary'
GEM_VERSION = YAML.load(File.read('VERSION.yml')).values.join('.').to_s
AUTHOR      = 'Carl P. Corliss'
EMAIL       = 'carl.corliss@nytimes.com'

spec = Gem::Specification.new do |s|
  s.name = GEM 
  s.version = GEM_VERSION
  s.author = AUTHOR
  s.email = EMAIL
  s.homepage = "http://www.nytimes.com/"
  s.platform = Gem::Platform::RUBY
  s.summary = "EventMachine/AMQP based event handling client"
  s.files = manifest_files()
  s.require_path = "lib"
  s.test_files = FileList["{test}/**/*test.rb"].to_a
  s.has_rdoc = false
  s.extra_rdoc_files = ["README.txt"]
  s.executables = File.read('Manifest.txt').split(/\n+/).select { |f| f =~  /^bin/ }.collect { |f| f[/bin\/(.*)$/,1] }

  s.default_executable = 'bin/emissary-setup'

  s.add_dependency("daemons", ">= 1.0.10")
  s.add_dependency('inifile', '>= 0.3.0')
  s.add_dependency('sys-cpu', '>= 0.6.2')
  s.add_dependency('bert',    '>= 1.1.2')
  s.add_dependency('amqp',    '= 0.6.7')
  s.add_dependency('carrot',  '>= 0.8.1')
  s.add_dependency('eventmachine', '>= 0.12.10')
  s.add_dependency('servolux',     '>= 0.9.4')
  s.add_dependency('uuid',         '>= 2.3.0')
  s.add_dependency('work_queue',   '>= 1.0.0')
end

require 'rake/gempackagetask'
Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end

require 'rake/clean'
CLEAN.include('pkg')


desc "install the gem locally"
task :install => [:package] do
  sh %{sudo gem install pkg/#{GEM}-#{GEM_VERSION}}
end

namespace :spec do
  desc "create a gemspec file"
  task :create do
    File.open("#{GEM}.gemspec", 'w') do |file|
      file.puts spec.to_ruby
    end
  end
end

namespace :manifest do
  desc "Rebuild Manifest file"
  task :rebuild do
    File.open('Manifest.txt', 'w') do |file|
      file.puts manifest_files.join("\n")
    end
  end
end

rake_tasks_glob = File.join(File.dirname(File.expand_path(__FILE__)), 'tasks', '*.rake')
Dir[rake_tasks_glob].sort.each do |ext| 
  load ext
end
