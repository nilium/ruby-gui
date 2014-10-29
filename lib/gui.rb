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
#  gui.rb
#    Root file for the gui gem. Imports other parts of the gem.


require 'glfw3'
require 'snow-data'
require 'snow-math'
require 'opengl-core'

require 'gui/version'
require 'gui/geom'
require 'gui/color'
require 'gui/selector'
require 'gui/selector/checks'
# require 'gui/selector_ext'
require 'gui/view'
require 'gui/window'
