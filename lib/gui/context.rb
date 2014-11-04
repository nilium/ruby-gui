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
#  context.rb
#    Context for a program using GUI


require 'glfw3'
require 'opengl-core'
require 'gui/gl/program'


module GUI

class Context

  DEFAULT_FRAG_SHADER = <<-GLSL.freeze
    #version 150

    smooth in vec4 color_var;
    smooth in vec2 texcoord_var;

    uniform sampler2D diffuse;

    out vec4 frag_color;

    void main() {
        frag_color = color_var * texture(diffuse, texcoord_var);
    }
  GLSL

  DEFAULT_VERT_SHADER = <<-GLSL.freeze
    #version 150

    in vec4 position;
    in vec2 texcoord;
    in vec4 color;

    smooth out vec4 color_var;
    smooth out vec2 texcoord_var;

    uniform mat4 projection;
    uniform mat4 modelview;

    void main() {
        gl_Position = projection * modelview * position;
        color_var = color;
        texcoord_var = texcoord;
    }
  GLSL

  FRAG_OUT0       = 0
  POSITION_ATTRIB = 1
  COLOR_ATTRIB    = 2
  TEXCOORD_ATTRIB = 3

  class << self

    attr_accessor :__active_context__
    attr_accessor :__glfw_inited__

    def __init_context__
      unless __glfw_inited__
        Glfw.init
        __glfw_inited__ = true
      end
      __set_window_flags__
    end

    def __set_window_flags__
      Glfw::Window.window_hint(Glfw::VISIBLE, GL::GL_FALSE)
      Glfw::Window.window_hint(Glfw::CONTEXT_VERSION_MAJOR, 3)
      Glfw::Window.window_hint(Glfw::CONTEXT_VERSION_MINOR, 2)
      Glfw::Window.window_hint(Glfw::OPENGL_FORWARD_COMPAT, GL::GL_TRUE)
      Glfw::Window.window_hint(Glfw::OPENGL_PROFILE, Glfw::OPENGL_CORE_PROFILE)
    end

    def post(blocklike = nil, &block)
      ctx = __active_context__
      raise "No active context to post block to" unless ctx
      ctx.post(blocklike) if blocklike
      ctx.post(block) if block
      self
    end

  end # singleton_class


  attr_accessor :windows
  attr_reader   :program


  def initialize
    self.class.__init_context__

    @realtime     = 0
    @windows      = []
    @textures     = {}
    @sequence     = 0
    @root_context = Glfw::Window.new(64, 64, '', nil, nil)
    @blocks       = []

    Window.bind_context(@root_context) do
      @program = ProgramObject.new
      @program.load_shader(GL::GL_VERTEX_SHADER, DEFAULT_VERT_SHADER)
      @program.load_shader(GL::GL_FRAGMENT_SHADER, DEFAULT_FRAG_SHADER)

      @program.bind_attrib(POSITION_ATTRIB, :position)
      @program.bind_attrib(TEXCOORD_ATTRIB, :texcoord)
      @program.bind_attrib(COLOR_ATTRIB,    :color)
      @program.bind_frag_data_location(FRAG_OUT0, :frag_color)

      @program.link
    end
  end

  def enable_realtime
    @realtime += 1
    self
  end

  def disable_realtime
    @realtime -= 1
    raise "Underflow on realtime counter" if @realtime < 0
    self
  end

  def realtime?
    @realtime > 0
  end

  def shared_context
    @root_context
  end

  def post(blocklike = nil, &block)
    raise ArgumentError, "No block given" unless blocklike || block
    @blocks << blocklike if blocklike
    @blocks << block if block
    self
  end

  def request_texture(name)
    interned = name.to_sym
    return @textures[interned] if @textures.include? interned

    File.open(name, 'rb') do |io|
      @textures[interned] = Texture.new(io)
    end
  end

  def release_texture(name)
    name = name.to_sym unless name.kind_of? Symbol
    if @textures.include? name
      @textures[name].release! { @texture.delete name }
    end
    self
  end

  def bind(*args, **kvargs)
    raise ArgumentError, "No block given" unless block_given?
    prev_context = self.class.__active_context__
    this_sequence = @sequence

    begin
      @sequence += 1
      self.class.__active_context__ = self

      yield(self, *args, **kvargs)
    ensure
      @sequence = this_sequence if @sequence > this_sequence
      # Guarantee proper context unwinding
      self.class.__active_context__ = prev_context
    end
  end

  def run_blocks(seq)
    seq.dup.each(&:call)
    seq.reject! { |b| !b.respond_to?(:done?) || b.done? }
  end

  def run(*args, **kvargs, &block)
    bind do
      this_sequence = @sequence
      while @sequence >= this_sequence && !@windows.empty?
        run_blocks @blocks

        if realtime?
          Glfw.poll_events
        else
          Glfw.wait_events
        end

        @windows.each do |window|
          window.dispatch_events
        end

        block[*args, **kvargs] if block

        @windows.each do |window|
          window.__swap_buffers__
        end
      end
    end
  end

  def quit
    @sequence -= 1
  end

end # Context

end # GUI
