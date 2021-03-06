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
#  gl.rb
#    OpenGL utilities


require 'opengl-core'
require 'snow-data'


module GUI


GLObject = Snow::CStruct.new do
  uint32_t :name
end


class GLCreateFailedError < StandardError ; end


class GLError < StandardError
  class << self ; alias_method :[], :new ; end

  attr_reader :code

  def initialize(code, message = nil)
    @code = code
    message = message.to_s
    super("GL Error: 0x#{code.to_s(16)} (#{
      case code
      when GL::GL_NO_ERROR                      then 'NO_ERROR'
      when GL::GL_INVALID_ENUM                  then 'INVALID_ENUM'
      when GL::GL_INVALID_VALUE                 then 'INVALID_VALUE'
      when GL::GL_INVALID_OPERATION             then 'INVALID_OPERATION'
      when GL::GL_INVALID_FRAMEBUFFER_OPERATION then 'INVALID_FRAMEBUFFER_OPERATION'
      when GL::GL_OUT_OF_MEMORY                 then 'OUT_OF_MEMORY'
      when GL::GL_STACK_UNDERFLOW               then 'STACK_UNDERFLOW'
      when GL::GL_STACK_OVERFLOW                then 'STACK_OVERFLOW'
      end
      })#{': ' unless message.empty?}#{message}")
  end

  def exception(message = nil)
    if message.nil?
      self
    else
      self.class.new(@code, message)
    end
  end
end


class << self

  def assert_no_gl_error(msg = nil)
    e = GL.glGetError
    warn GLError[e, msg] if e != GL::GL_NO_ERROR
    nil
  end

end


class GLObject

  alias_method :__base_initialize__, :initialize

  def initialize
    __base_initialize__
    @refs = 1
  end

  def retain
    @refs += 1
    if block_given?
      begin
        yield self
      ensure
        release
      end
    end
  end

  def release
    @refs -= 1
    if @refs == 0
      yield self if block_given?
      destroy
    elsif @refs < 0
      raise "Object with retain count of zero released"
    end
  end

end


class BufferObject < GLObject

  class << self

    def target_binding(target)
      case target
      when GL::GL_ARRAY_BUFFER then GL::GL_ARRAY_BUFFER_BINDING
      when GL::GL_ELEMENT_ARRAY_BUFFER then GL::GL_ELEMENT_ARRAY_BUFFER_BINDING
      else raise ArgumentError,
        "Reserved binding for 0x#{target.to_s(16)} not provided"
      end
    end

    def preserve_binding(target, *args, **kvargs)
      raise ArgumentError, "No block given" unless block_given?

      prev_name = GLObject.new
      GL.glGetIntegerv(target_binding(target), prev_name.address)
      begin
        yield(*args, **kvargs)
      ensure
        GL.glBindBuffer(target, prev_name.name)
      end
    end

  end # singleton_class

  attr_accessor :target

  def initialize
    super
    self.name = GL.glGenBuffers(1)
    raise GLCreateFailedError, "Unable to create buffer object" if self.name == 0
    @target = nil
  end

  def bind(target = nil, &block)
    target ||= @target || GL::GL_ARRAY_BUFFER
    @target ||= target
    if block
      self.class.preserve_binding(target) do
        GL.glBindBuffer(target, self.name)
        block[self]
      end
    else
      GL.glBindBuffer(target, self.name)
      self
    end
  end

  def destroy
    if self.name != 0
      GL.glDeleteTextures(1, self.address)
      self.name = 0
    end
  end

end # BufferObject


class VertexArrayObject < GLObject

  class << self

    def preserve_binding(*args, **kvargs)
      raise ArgumentError, "No block given" unless block_given?

      prev_name = GLObject.new
      GL.glGetIntegerv(GL::GL_VERTEX_ARRAY_BINDING, prev_name.address)
      begin
        yield(*args, **kvargs)
      ensure
        GL.glBindVertexArray(prev_name.name)
      end
    end

  end

  def initialize
    super
    GL.glGenVertexArrays(1, self.address)
    raise GLCreateFailedError, "Unable to create vertex array object" if self.name == 0
  end

  def bind(&block)
    if block
      self.class.preserve_binding do
        GL.glBindVertexArray(self.name)
        block[self]
      end
    else
      GL.glBindVertexArray(self.name)
      self
    end
  end

  def destroy
    if self.name != 0
      GL.glDeleteVertexArrays(1, self.address)
      self.name = 0
    end
  end

end # VertexArrayObject

end
