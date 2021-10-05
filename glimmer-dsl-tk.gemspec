# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: glimmer-dsl-tk 0.0.12 ruby lib .

Gem::Specification.new do |s|
  s.name = "glimmer-dsl-tk".freeze
  s.version = "0.0.12"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze, ".".freeze]
  s.authors = ["AndyMaleh".freeze]
  s.date = "2021-10-09"
  s.description = "Glimmer DSL for Tk (Ruby Desktop Development GUI Library)".freeze
  s.email = "andy.am@gmail.com".freeze
  s.executables = ["girb".freeze]
  s.extra_rdoc_files = [
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md"
  ]
  s.files = [
    "CHANGELOG.md",
    "LICENSE.txt",
    "README.md",
    "VERSION",
    "bin/girb",
    "bin/girb_runner.rb",
    "glimmer-dsl-tk.gemspec",
    "icons/glimmer.png",
    "lib/glimmer-dsl-tk.rb",
    "lib/glimmer/data_binding/tk/list_selection_binding.rb",
    "lib/glimmer/data_binding/tk/widget_binding.rb",
    "lib/glimmer/dsl/tk/attribute_expression.rb",
    "lib/glimmer/dsl/tk/bind_expression.rb",
    "lib/glimmer/dsl/tk/block_attribute_expression.rb",
    "lib/glimmer/dsl/tk/data_binding_expression.rb",
    "lib/glimmer/dsl/tk/dsl.rb",
    "lib/glimmer/dsl/tk/list_selection_data_binding_expression.rb",
    "lib/glimmer/dsl/tk/root_expression.rb",
    "lib/glimmer/dsl/tk/shine_data_binding_expression.rb",
    "lib/glimmer/dsl/tk/widget_expression.rb",
    "lib/glimmer/tk/button_proxy.rb",
    "lib/glimmer/tk/entry_proxy.rb",
    "lib/glimmer/tk/frame_proxy.rb",
    "lib/glimmer/tk/label_proxy.rb",
    "lib/glimmer/tk/list_proxy.rb",
    "lib/glimmer/tk/notebook_proxy.rb",
    "lib/glimmer/tk/root_proxy.rb",
    "lib/glimmer/tk/treeview_proxy.rb",
    "lib/glimmer/tk/widget_proxy.rb",
    "samples/hello/hello_combo.rb",
    "samples/hello/hello_computed.rb",
    "samples/hello/hello_computed/contact.rb",
    "samples/hello/hello_list_multi_selection.rb",
    "samples/hello/hello_list_single_selection.rb",
    "samples/hello/hello_tab.rb",
    "samples/hello/hello_world.rb"
  ]
  s.homepage = "http://github.com/AndyObtiva/glimmer-dsl-tk".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.2.28".freeze
  s.summary = "Glimmer DSL for Tk".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<glimmer>.freeze, ["~> 2.1.2"])
    s.add_runtime_dependency(%q<puts_debuggerer>.freeze, ["~> 0.13.1"])
    s.add_runtime_dependency(%q<tk>.freeze, ["~> 0.4.0"])
    s.add_development_dependency(%q<rspec>.freeze, ["~> 3.5.0"])
    s.add_development_dependency(%q<rdoc>.freeze, ["~> 3.12"])
    s.add_development_dependency(%q<bundler>.freeze, [">= 1.0"])
    s.add_development_dependency(%q<jeweler>.freeze, [">= 2.3.9", "< 3.0.0"])
    s.add_development_dependency(%q<rake-tui>.freeze, [">= 0.2.1"])
    s.add_development_dependency(%q<coveralls>.freeze, ["= 0.8.23"])
    s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.16.1"])
    s.add_development_dependency(%q<simplecov-lcov>.freeze, ["~> 0.7.0"])
  else
    s.add_dependency(%q<glimmer>.freeze, ["~> 2.1.2"])
    s.add_dependency(%q<puts_debuggerer>.freeze, ["~> 0.13.1"])
    s.add_dependency(%q<tk>.freeze, ["~> 0.4.0"])
    s.add_dependency(%q<rspec>.freeze, ["~> 3.5.0"])
    s.add_dependency(%q<rdoc>.freeze, ["~> 3.12"])
    s.add_dependency(%q<bundler>.freeze, [">= 1.0"])
    s.add_dependency(%q<jeweler>.freeze, [">= 2.3.9", "< 3.0.0"])
    s.add_dependency(%q<rake-tui>.freeze, [">= 0.2.1"])
    s.add_dependency(%q<coveralls>.freeze, ["= 0.8.23"])
    s.add_dependency(%q<simplecov>.freeze, ["~> 0.16.1"])
    s.add_dependency(%q<simplecov-lcov>.freeze, ["~> 0.7.0"])
  end
end

