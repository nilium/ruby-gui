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


module GUI

class Texture

  TextureName = Snow::CStruct.new { uint32_t :name }

  LOAD_TEXTURE_BLOCK = -> (data, x, y, components) do
    internalFormat =
      case components
      when STBI::COMPONENTS_GREY        then Gl::GL_RED
      when STBI::COMPONENTS_GREY_ALPHA  then Gl::GL_RG
      when STBI::COMPONENTS_RGB         then Gl::GL_RGB
      when STBI::COMPONENTS_RGB_ALPHA   then Gl::GL_RGBA
      else raise ArgumentError, "Invalid number of texture components"
      end

    name = TextureName.new
    raise "Unable to allocate texture name" unless name

    Gl.glGetIntegerv(Gl::GL_TEXTURE_BINDING_2D, name.address)
    prev_name = name.name

    Gl.glGenTextures(1, name.address)
    Gl.glBindTexture(Gl::GL_TEXTURE_2D, name.name)

    Gl.glTexParameteri(Gl::GL_TEXTURE_2D, Gl::GL_TEXTURE_WRAP_S, Gl::GL_CLAMP_TO_EDGE)
    Gl.glTexParameteri(Gl::GL_TEXTURE_2D, Gl::GL_TEXTURE_WRAP_T, Gl::GL_CLAMP_TO_EDGE)
    Gl.glTexParameteri(Gl::GL_TEXTURE_2D, Gl::GL_TEXTURE_MIN_FILTER, Gl::GL_LINEAR)
    Gl.glTexParameteri(Gl::GL_TEXTURE_2D, Gl::GL_TEXTURE_MAG_FILTER, Gl::GL_LINEAR)

    Gl.glTexImage2D(
      Gl::GL_TEXTURE_2D,      # target
      0,                      # level
      format,                 # internal format
      x, y,                   # width, height
      0,                      # border
      format,                 # format
      Gl::GL_UNSIGNED_BYTE,   # typep
      data
      )

    glBindTexture(Gl::GL_TEXTURE_2D, prev_name)

    name
  end


  # Allocates a new texture using the given IO object.
  # If a block is given, the texture is only valid in the scope of the block
  # unless retained elsewhere.
  def initialize(io, &block)
    @name = STBI.load_image(io, STBI::COMPONENTS_DEFAULT, &LOAD_TEXTURE_BLOCK)
    @refs = 0
    retain(&block)
  end

  def retain
    @refs += 1

    if block_given?
      yield self
      release
    end
  end

  def release
    @refs -= 1
    if @refs == 0
      # If it's necessary to do anything else to release the object, pass it
      # to a block first.
      yield self if block_given?

      glDeleteTextures(1, @name.address)
    end
  end

end # Texture

end # GUI
