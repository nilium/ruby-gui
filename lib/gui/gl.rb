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
      when Gl::GL_NO_ERROR                      then 'NO_ERROR'
      when Gl::GL_INVALID_ENUM                  then 'INVALID_ENUM'
      when Gl::GL_INVALID_VALUE                 then 'INVALID_VALUE'
      when Gl::GL_INVALID_OPERATION             then 'INVALID_OPERATION'
      when Gl::GL_INVALID_FRAMEBUFFER_OPERATION then 'INVALID_FRAMEBUFFER_OPERATION'
      when Gl::GL_OUT_OF_MEMORY                 then 'OUT_OF_MEMORY'
      when Gl::GL_STACK_UNDERFLOW               then 'STACK_UNDERFLOW'
      when Gl::GL_STACK_OVERFLOW                then 'STACK_OVERFLOW'
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
    e = Gl.glGetError
    warn GLError[e, msg] if e != Gl::GL_NO_ERROR
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
      raise ""
    end
  end

end


class BufferObject < GLObject

  class << self

    def target_binding(target)
      case target
      when Gl::GL_ARRAY_BUFFER then Gl::GL_ARRAY_BUFFER_BINDING
      when Gl::GL_ELEMENT_ARRAY_BUFFER then Gl::GL_ELEMENT_ARRAY_BUFFER_BINDING
      else raise ArgumentError,
        "Revered binding for 0x#{target.to_s(16)} not provided"
      end
    end

    def preserve_binding(target, *args, **kvargs)
      raise ArgumentError, "No block given" unless block_given?

      prev_name = GLObject.new
      Gl.glGetIntegerv(target_binding(target), prev_name.address)
      begin
        yield(*args, **kvargs)
      ensure
        Gl.glBindBuffer(target, prev_name.name)
      end
    end

  end # singleton_class

  def initialize
    super
    Gl.glGenBuffers(1, self.address)
  end

  def bind(target = nil, &block)
    @target ||= (target ||= @target || Gl::GL_ARRAY_BUFFER)
    if block
      self.class.preserve_binding do
        Gl.glBindBuffer(target, self.name)
        block[self]
      end
    else
      Gl.glBindBuffer(target, self.name)
    end
  end

  def destroy
    if self.name != 0
      Gl.glDeleteTextures(1, self.address)
      self.name = 0
    end
  end

end # BufferObject


class VertexArrayObject < GLObject

  class << self

    def preserve_binding(*args, **kvargs)
      raise ArgumentError, "No block given" unless block_given?

      prev_name = GLObject.new
      Gl.glGetIntegerv(Gl::GL_VERTEX_ARRAY_BINDING, prev_name.address)
      begin
        yield(*args, **kvargs)
      ensure
        Gl.glUseProgram(prev_name.name)
      end
    end

  end

  def initialize
    super
    Gl.glGenVertexArrays(1, self.address)
  end

  def bind(&block)
    if block
      self.class.preserve_binding do
        Gl.glBindVertexArray(self.name)
        block[self]
      end
    else
      Gl.glBindVertexArray(self.name)
    end
  end

  def destroy
    if self.name != 0
      Gl.glDeleteVertexArrays(1, self.address)
      self.name = 0
    end
  end

end # VertexArrayObject

end
