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
#  extconf.rb
#    Configuration for C chunks of the GUI gem


require 'mkmf'


# Compile as C99
$CFLAGS += " -std=c99 -march=native"

OptKVPair = Struct.new(:key, :value)

option_mappings = {
  '-D'              => OptKVPair[:build_debug, true],
  '--debug'         => OptKVPair[:build_debug, true],
  '-ND'             => OptKVPair[:build_debug, false],
  '--release'       => OptKVPair[:build_debug, false]
}

options = {
  :build_debug => false
}

ARGV.each do |arg|
  pair = option_mappings[arg]
  if pair
    options[pair.key] = pair.value
  else
    $stderr.puts "Unrecognized install option: #{arg}"
  end
end

if options[:build_debug]
  $CFLAGS += " -g -O0"
  $stderr.puts "Building extension in debug mode"
else
  # mfpmath is ignored on clang, FYI
  if `cc -v 2>&1`.include?('(clang-')
    $CFLAGS += " -Ofast -O4 -flto -emit-llvm"
  else
    $CFLAGS += " -O3"
  end
  $CFLAGS += " -fno-strict-aliasing"
  $stderr.puts "Building extension in release mode"
end

create_makefile('gui/selector_ext', 'gui_selectors/')
