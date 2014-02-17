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
#  window.rb
#    Window base class


require 'set'
require 'glfw3'
require 'gui/context'
require 'gui/view'
require 'gui/geom'
require 'gui/driver'
require 'gui/gl/texture'
require 'gui/event'


module GUI

class Window < View


  class << self

    def bind_context(window)
      if block_given?
        current = Glfw::Window.current_context
        begin
          bind_context(window)
          yield
        ensure
          bind_context(current)
        end
      elsif window
        puts "Binding context for #{window}"
        window.make_context_current
      else
        puts "Unbinding window context"
        Glfw::Window.unset_context
      end

      nil
    end

  end


  MAX_INVALIDATE_LOOPS = 5

  attr_accessor :background

  def initialize(frame, title, context = nil)
    context ||= Context.__active_context__

    @title = title
    @background = Color.dark_grey
    @in_update = []
    @context = context

    super(frame)

    __window__
  end

  def __window__
    @glfw_window ||= begin
      @context.class.__set_window_flags__

      window = ::Glfw::Window.new(
        @frame.size.x,
        @frame.size.y,
        @title,
        nil,
        @context.shared_context
        ).set_position(*@frame.origin)

      window.set_size_callback do |w, x, y|
        unless @in_update.include? :frame
          @in_update << :frame
          @frame.size.x = x
          @frame.size.y = y
          @in_update.delete :frame
          invalidate(bounds)
        end
      end

      window.set_position_callback do |w, x, y|
        unless @in_update.include? :frame
          @in_update << :frame
          @frame.origin.x = x
          @frame.origin.y = y
          @in_update.delete :frame
        end
      end

      window.set_close_callback do |w|
        close
      end

      @context.windows << self

      window
    end
  end

  def scale_factor
    if @glfw_window
      @glfw_window.framebuffer_size[0] / @frame.size.x
    else
      1.0
    end
  end

  def frame=(new_frame)
    unless @in_update.include? :frame
      __window__
        .set_position(new_frame.origin.x, new_frame.origin.y)
        .set_size(new_frame.size.x, new_frame.size.y)
    end
    super
  end

  def draw
  end

  def show
    __window__.show
  end

  def hide
    __window__.hide
  end

  # May be overridden to change whether clicking the close button actually
  # closes the window. A super call destroys the window, so any further access
  # to it is currently undefined behavior.
  def close
    if @glfw_window
      prev_window = @glfw_window
      @glfw_window = nil
      # Note: post this since otherwise destroying the window here will do
      # Bad Things(r) if #close is called from a callback (which it is). Be
      # very careful about that.
      @context.post { prev_window.destroy }
      @context.windows.delete(self)
    end
  end

  def __swap_buffers__
    return unless @invalidated

    self.class.bind_context(__window__) do
      loops = MAX_INVALIDATE_LOOPS

      @context.program.use do |prog|

        begin

          region = @invalidated
          @invalidated = nil

          if !region.empty?
            Gl.glEnable(Gl::GL_SCISSOR_TEST)
            Gl.glScissor(
              region.x * scale_factor,
              (@frame.height - region.bottom) * scale_factor,
              region.width * scale_factor,
              region.height * scale_factor
              )

            Gl.glClearColor(*@background)
            Gl.glClear(Gl::GL_COLOR_BUFFER_BIT)

            # draw_subviews (those within region)

            Gl.glDisable(Gl::GL_SCISSOR_TEST)
          end

          loops -= 1
        end until @invalidated.nil? || loops <= 0

        __window__.swap_buffers
      end

      if @invalidated
        $stderr.puts "Terminating window invalidation loop after #{MAX_INVALIDATE_LOOPS} runs"
      end
    end
  end

end # Window

end # GUI
