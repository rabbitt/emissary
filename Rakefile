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
    File.join(base_path, 'VERSION.yml')
  ]
  
  Find.find(*search_paths) do |path|
    if File.directory? path
      File.basename(path)[/^\./] ? Find.prune : next
    end
    manifest_files << path.gsub(base_path + ::File::SEPARATOR, '')
  end
  
  manifest_files
end

spec = Gem::Specification.new do |s|
  s.name = "emissary"
  s.version = YAML.load(File.read('VERSION.yml')).values.join('.').to_s
  s.author = "Carl P. Corliss"
  s.email = "carl.corliss@nytimes.com"
  s.homepage = "http://www.nytimes.com/"
  s.platform = Gem::Platform::RUBY
  s.summary = "EventMachine/AMQP based event handling client"
  s.files = manifest_files()
  s.require_path = "lib"
  s.test_files = FileList["{test}/**/*test.rb"].to_a
  s.has_rdoc = false
  s.extra_rdoc_files = ["README.txt"]
  s.executables = ['emissary', 'emissary-setup']

  s.default_executable = 'bin/emissary-setup'

  s.add_dependency("daemons", ">= 1.0.10")
  s.add_dependency('inifile', '>= 0.3.0')
  s.add_dependency('sys-cpu', '>= 0.6.2')
  s.add_dependency('bert', '>= 1.1.2')
  s.add_dependency('amqp',    '>= 0.6.7')
  s.add_dependency('carrot', '>= 0.7.1')
  s.add_dependency('eventmachine', '>= 0.12.10')
  s.add_dependency('servolux', '>= 0.9.4')
  s.add_dependency('uuid', '>= 2.3.0')
  s.add_dependency('work_queue', '>= 1.0.0')
end

require 'rake/gempackagetask'
Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = true
end

require 'rake/clean'
CLEAN.include('pkg')

rake_tasks_glob = File.join(File.dirname(File.expand_path(__FILE__)), 'tasks', '*.rake')
Dir[rake_tasks_glob].sort.each do |ext| 
  load ext
end