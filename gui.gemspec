#  Copyright 2014 Noel Cower
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
#  -----------------------------------------------------------------------------
#
#  gui.gemspec
#    Gemspec for the gui gem.

require File.expand_path('../lib/gui/version.rb', __FILE__)


Gem::Specification.new do |s|
  s.name        = 'gui'
  s.version     = GUI::GUI_VERSION
  s.summary     = 'Some sort of GUI gem.'
  s.description = 'A GUI gem for Ruby.'
  s.authors     = [ 'Noel Cower' ]
  s.email       = 'ncower@gmail.com'
  s.files       = Dir.glob('lib/**/*.rb') +
                  [ 'COPYING', 'README.md' ]
  s.homepage    = 'https://github.com/nilium/ruby-gui'
  s.license     = GUI::GUI_LICENSE_BRIEF
  s.has_rdoc    = true
  s.extra_rdoc_files = [
      'README.md',
      'COPYING'
  ]

  s.add_runtime_dependency 'glfw3',       '~> 0.4', '>= 0.4.5'
  s.add_runtime_dependency 'opengl-core', '~> 1.3', '>= 1.3.2'
  s.add_runtime_dependency 'snow-math',   '~> 1.7', '>= 1.7.1'
  s.add_runtime_dependency 'snow-data',   '~> 1.3', '>= 1.3.0'
  s.add_runtime_dependency 'stb-image',   '~> 1.0', '>= 1.0.1'
end
