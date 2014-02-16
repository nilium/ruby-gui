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
#  texture.rb
#    Wrapper around GL texture names.


require 'stb-image'
require 'snow-data'
require 'gui/gl'


module GUI

class Texture < GLObject

  class << self

    def load_from_io(io)
      STBI.load_image(io, STBI::COMPONENTS_DEFAULT) do |data, x, y, components|
        self.new.bind(GL_TEXTURE_2D) do |tex|
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
          glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)

          glTexImage2D(
            GL_TEXTURE_2D, 0, format, x, y, 0, format, GL_UNSIGNED_BYTE, data)

          tex.retain
        end
      end
    end

    def target_binding(target)
      case target
      when GL_TEXTURE_1D then GL_TEXTURE_BINDING_1D
      when GL_TEXTURE_2D then GL_TEXTURE_BINDING_2D
      when GL_TEXTURE_3D then GL_TEXTURE_BINDING_3D
      else raise NotImplementError,
        "No binding getter provided for 0x#{target.to_s(16)} yet"
      end
    end

    def preserve_binding(target, *args, **kvargs)
      raise ArgumentError, "No block given" unless block_given?

      prev_name = GLObject.new
      Gl.glGetIntegerv(target_binding(target), prev_name.address)
      begin
        yield(*args, **kvargs)
      ensure
        Gl.glBindTexture(target, prev_name.name)
      end
    end

  end # singleton_class


  def initialize
    super()
    glGenTextures(1, self.address)
  end

  def bind(target = nil, &block)
    @target ||= (target ||= @target || Gl.GL_TEXTURE_2D)
    if block
      self.class.preserve_binding(target) do
        glBindTexture(target, self.name)
        block[self]
      end
    else
      glBindTexture(target, self.name)
    end
  end

  def destroy
    if self.name != 0
      glDeleteTextures(1, self.address)
      self.name = 0
    end
  end

end # Texture

end # GUI
