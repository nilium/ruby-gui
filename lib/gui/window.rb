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


require 'glfw3'
require 'gui/context'
require 'gui/view'
require 'gui/geom'
require 'set'


module GUI

class Window < View

  MAX_INVALIDATE_LOOPS = 5

  def initialize(width, height, title, context = nil)
    context ||= Context.__active_context__
    context.windows << self

    @in_update = []
    @context = context
    @glfw_window = ::Glfw::Window.new(width, height, title, nil, context.shared_context)

    @glfw_window.set_size_callback do |window, x, y|
      unless @in_update.include? :frame
        @in_update << :frame
        @frame.size.x = x
        @frame.size.y = y
        @in_update.delete :frame
        invalidate(bounds)
      end
    end

    @glfw_window.set_position_callback do |window, x, y|
      unless @in_update.include? :frame
        @in_update << :frame
        @frame.origin.x = x
        @frame.origin.y = y
        @in_update.delete :frame
      end
    end

    @glfw_window.set_close_callback do |window|
      @glfw_window.should_close = false
      close
    end

    super(Rect[*@glfw_window.position, *@glfw_window.size])
  end

  def scale_factor
    @glfw_window.framebuffer_size[0] / @frame.size.x
  end

  def frame=(new_frame)
    unless @in_update.include? :frame
      @glfw_window
        .set_position(new_frame.origin.x, new_frame.origin.y)
        .set_size(new_frame.size.x, new_frame.size.y)
    end
    super
  end

  def draw
    @glfw_window.make_context_current
    draw
    super
  end

  def show
    @glfw_window.show
  end

  def hide
    @glfw_window.hide
  end

  # May be overridden to change whether clicking the close button actually
  # closes the window.
  def close
    @glfw_window.should_close = true
    @context.windows.delete(self)
  end

  def __swap_buffers__
    return unless @invalidated

    last_ctx = Glfw::Window.current_context
    begin
      @glfw_window.make_context_current
      loops = MAX_INVALIDATE_LOOPS

      begin
        region = @invalidated
        @invalidated = nil

        if !region.empty?
          Gl::glEnable(Gl::GL_SCISSOR_TEST)
          Gl::glScissor(
            region.x * scale_factor,
            (@frame.height - region.bottom) * scale_factor,
            region.width * scale_factor,
            region.height * scale_factor
            )

          # draw_subviews (those within region)

          Gl::glClear(Gl::GL_COLOR_BUFFER_BIT)
          Gl::glDisable(Gl::GL_SCISSOR_TEST)
        end

        loops -= 1
      end until @invalidated.nil? || loops <= 0
      @glfw_window.swap_buffers

      if @invalidated
        $stderr.puts "Terminating window invalidation loop after #{MAX_INVALIDATE_LOOPS} runs"
      end

    ensure
      if last_ctx
        last_ctx.make_context_current
      else
        Glfw::Window.unset_context
      end
    end
  end

end # Window

end # GUI
