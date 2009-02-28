Gem::Specification.new do |s|
  s.name = "slicehost-dns"
  s.version = "0.3.2"
  s.date = "2009-02-10"
  s.summary = "Manages DNS settings on your slicehost account via a YAML file"
  s.email = "matt@flowerpowered.com"
  s.homepage = "http://github.com/mattly/slicehost-dns"
  s.description = "because YAML is the one true config format"
  s.has_rdoc = false
  s.authors = ["Matthew Lyon"]
  s.files = ["LICENSE", "Manifest", "README.mkdn", "bin/slicehost-dns", "lib/example.yml", "lib/reconciler.rb", "lib/record.rb", "lib/zone.rb", "lib/slicehost-dns.rb"]
  s.executables = ['slicehost-dns']
  s.default_executable = 'slicehost-dns'
  s.require_paths = ['lib','bin']
  
  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2
    if current_version >= 3 then
      s.add_runtime_dependency(%q<activeresource>)
    else
      s.add_dependency(%q<activeresource>)
    end
  else
    s.add_dependency(%q<activeresource>)
  end
end