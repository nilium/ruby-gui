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

    def __load_texture_data__(target, data, x, y, components)
      format =
        case components
        when STBI::COMPONENTS_GREY then Gl::GL_RED
        when STBI::COMPONENTS_GREY_ALPHA then Gl::GL_RG
        when STBI::COMPONENTS_RGB then Gl::GL_RGB
        when STBI::COMPONENTS_RGB_ALPHA then Gl::GL_RGBA
        else raise ArgumentError, "Invalid components: #{components}"
        end

      Gl.glTexParameteri(target, Gl::GL_TEXTURE_WRAP_S, Gl::GL_CLAMP_TO_EDGE)
      Gl.glTexParameteri(target, Gl::GL_TEXTURE_WRAP_T, Gl::GL_CLAMP_TO_EDGE)
      Gl.glTexParameteri(target, Gl::GL_TEXTURE_MIN_FILTER, Gl::GL_LINEAR)
      Gl.glTexParameteri(target, Gl::GL_TEXTURE_MAG_FILTER, Gl::GL_LINEAR)

      Gl.glTexImage2D(target, 0, format, x, y, 0, format, Gl::GL_UNSIGNED_BYTE, data)
    end

    # Loads a texture using the given IO object for reading. If a block is
    # given, the texture object, data, width, height, and number of components
    # will be passed to the block for loading -- the result of the block is
    # returned. Otherwise, the texture is loaded as a standard 2D texture and
    # the texture object is returned.
    #
    # In block form, the texture's target is assumed to either be known or
    # acquired from the texture object's target member.
    def load_from_io(io, target = nil, &block)
      target ||= Gl::GL_TEXTURE_2D
      STBI.load_image(io, STBI::COMPONENTS_DEFAULT) do |data, x, y, components|
        self.new.bind(target) do |tex|
          if block
            block[tex, data, x, y, components]
          else
            __load_texture_data__(target, data, x, y, components)
            tex
          end
        end
      end
    end

    def target_binding(target)
      case target
      when Gl::GL_TEXTURE_1D then Gl::GL_TEXTURE_BINDING_1D
      when Gl::GL_TEXTURE_2D then Gl::GL_TEXTURE_BINDING_2D
      when Gl::GL_TEXTURE_3D then Gl::GL_TEXTURE_BINDING_3D
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
    Gl.glGenTextures(1, self.address)
    @target = nil
    raise GLCreateFailedError, "Unable to create texture" if self.name == 0
  end

  def bind(target = nil, &block)
    target ||= @target || Gl::GL_TEXTURE_2D
    @target ||= target
    if block
      self.class.preserve_binding(target) do
        Gl.glBindTexture(target, self.name)
        block[self]
      end
    else
      Gl.glBindTexture(target, self.name)
    end
  end

  def destroy
    if self.name != 0
      Gl.glDeleteTextures(1, self.address)
      self.name = 0
    end
  end

end # Texture

end # GUI
