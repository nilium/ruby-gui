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
#  program.rb
#    Basic shader program object


require 'snow-data'
require 'gui/gl'


module GUI

class ProgramObject < GLObject


  ShaderInt = Snow::CStruct.new { int32_t :value }


  class << self

    def preserve_binding(*args, **kvargs)
      raise ArgumentError, "No block given" unless block_given?

      prev_name = GLObject.new
      GL.glGetIntegerv(GL::GL_CURRENT_PROGRAM, prev_name.address)
      begin
        yield(*args, **kvargs)
      ensure
        GL.glUseProgram(prev_name.name)
      end
    end

  end # singleton_class


  def initialize
    super
    @attached_shaders   = []
    @uniform_locations  = {}
    self.name           = GL.glCreateProgram()
    raise GLCreateFailedError, "Unable to create program object" unless self.name > 0
  end

  def load_shader(kind, source)
    source = source.read if source.kind_of?(IO)
    shader = GL.glCreateShader(kind)
    raise GLCreateFailedError, "Unable to create shader" unless shader > 0

    # Actually a good situation to use packed strings in.
    GL.glShaderSource(shader, source)
    GL.glCompileShader(shader)

    int = ShaderInt.new

    GL.glGetShaderiv(shader, GL::GL_COMPILE_STATUS, int.address)
    if int.value != GL::GL_TRUE
      GL.glGetShaderiv(shader, GL::GL_INFO_LOG_LENGTH, int.address)
      log_length = int.value
      log = "(no log available)"
      if log_length > 0
        log = ' ' * log_length
        GL.glGetShaderInfoLog(shader, log.bytesize, 0, log)
      end

      GL.glDeleteShader(shader)

      raise GLCreateFailedError, "Unable to compile shader: #{log}"
    end

    GL.glAttachShader(self.name, shader)
    @attached_shaders << shader

    self
  end

  def link
    program = self.name
    GL.glLinkProgram(program)

    int = ShaderInt.new

    GL.glGetProgramiv(program, GL::GL_LINK_STATUS, int.address)
    if int.value != GL::GL_TRUE
      GL.glGetProgramiv(program, GL::GL_INFO_LOG_LENGTH, int.address)
      log_length = int.value
      log = "(no log available)"
      if log_length > 0
        log = ' ' * log_length
        GL.glGetProgramInfoLog(shader, log.bytesize, 0, log)
      end

      raise GLCreateFailedError, "Unable to link program: #{log}"
    end

    destroy_attached_shaders
    @uniform_locations.clear

    self
  end

  def use(&block)
    if block
      self.class.preserve_binding do
        GL.glUseProgram(self.name)
        block[self]
      end
    else
      GL.glUseProgram(self.name)
      self
    end
  end

  def destroy_attached_shaders
    program_exists = self.name != 0
    @attached_shaders.each do |shader|
      GL.glDetachShader(self.name, shader) if program_exists
      GL.glDeleteShader(shader)
    end.clear
    self
  end

  def bind_attrib(index, name)
    GL.glBindAttribLocation(self.name, index, name.to_s)
    self
  end

  def bind_frag_data_location(color_number, name)
    GL.glBindFragDataLocation(self.name, color_number, name.to_s)
    self
  end

  # name => Symbol
  # Returns the uniform location for the named uniform. Caches the result for
  # repeated access.
  def uniform_location(name)
    @uniform_locations[name.to_sym] ||= begin
      GL.glGetUniformLocation(self.name, name.to_s)
    end
  end

  alias_method :[], :uniform_location

  def destroy
    destroy_attached_shaders

    if @program != 0
      GL.glDeleteProgram(@program)
    end
  end

end # ProgramObject

end # GUI
