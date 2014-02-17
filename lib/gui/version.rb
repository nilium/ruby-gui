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
#  version.rb
#    Version information for the gui gem.


module GUI

  GUI_VERSION           = '0.0.1.pre2'.freeze
  GUI_LICENSE_BRIEF     = 'Apache 2.0 License'.freeze
  GUI_GEM_ROOT          = File.expand_path('../../../', __FILE__).freeze

  # Don't load the license unless it's needed.
  define_singleton_method(:GUI_LICENSE_FULL, &-> do
    File.open("#{GUI_GEM_ROOT}/COPYING") do |io|
      io.read
    end.freeze.tap do |license_txt|
      ::GUI::set_const(:GUI_LICENSE_FULL, license_txt)
    end
  end)

end # GUI
