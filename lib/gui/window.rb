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
require 'gui/event_dispatch'


module GUI

class Window < View

  include EventDispatch


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
        window.make_context_current
      else
        Glfw::Window.unset_context
      end

      nil
    end

  end


  attr_accessor :background

  def initialize(frame, title, context = nil)
    context ||= Context.__active_context__

    @title = title
    @background = Color.dark_grey
    @in_update = []
    @context = context

    super(frame)

    self.class.bind_context(__window__) do
      @driver = BufferedDriver.new
    end
  end

  def title
    @title
  end

  def title=(new_title)
    @title = new_title.to_s
    @glfw_window.title = @title if @glfw_window
    new_title
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

      window.size_callback = -> (wnd, x, y) do
        unless @in_update.include? :frame
          @frame.size.x = x
          @frame.size.y = y
          invalidate(bounds)
          post_event Event[self, :resized, target: self, frame: @frame.dup]
        end
      end

      window.framebuffer_size_callback = -> (wnd, x, y) do
        invalidate(bounds)
      end

      window.set_position_callback do |w, x, y|
        unless @in_update.include? :frame
          @frame.origin.x = x
          @frame.origin.y = y
          post_event Event[self, :resized, target: self, frame: @frame.dup]
        end
      end

      window.set_refresh_callback do |w|
        invalidate(bounds)
      end

      window.set_close_callback do |w|
        post_event Event[self, :close_button, target: self]
      end

      window.mouse_button_callback = -> (wnd, button, action, mods) do
        pos = Vec2[*wnd.cursor_pos]
        target = self.views_containing_point(pos).first || self
        post_event Event[self, :mouse_button,
          target: target,
          action: action,
          button: button,
          modifiers: mods,
          position: target.convert_from_root(pos, pos)
        ]
      end

      @context.windows << self

      window
    end
  end

  def handle_event(event)
    case event.kind
    when :close_button
      event.stop_propagation!
      close if !event.cancelled?

    else super
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

  def draw(driver)
  end

  def show
    __window__.show
    invalidate
    self
  end

  def hide
    __window__.hide
    self
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

  def __prepare_uniforms__(program)
    ortho = Mat4.new
    modelview = Mat4.new

    mv_loc = program.uniform_location(:modelview)
    pr_loc = program.uniform_location(:projection)

    Mat4.orthographic(
      0.0, @frame.size.x,
      0.0, @frame.size.y,
      -1.0, 1.0,
      ortho
      )

    modelview.load_identity.
      translate!(0.0, window.frame.size.y, 0.0).
      multiply_mat4!(Mat4.new.scale!(1.0, -1.0, 1.0))

    Gl.glUniformMatrix4fv(pr_loc, 1, Gl::GL_FALSE, ortho.address)
    Gl.glUniformMatrix4fv(mv_loc, 1, Gl::GL_FALSE, modelview.address)
  end

  def __swap_buffers__
    return unless @invalidated

    window = __window__
    self.class.bind_context(window) do
      @context.program.use do |prog|
        @driver.request_uniform_cb = -> (name) { prog[name] }
        @driver.origin = Vec2[0.0, 0.0]

        __prepare_uniforms__(prog)

        region = @invalidated
        @invalidated = nil

        if !region.empty?
          Gl.glEnable(Gl::GL_BLEND)
          Gl.glBlendFunc(Gl::GL_SRC_ALPHA, Gl::GL_ONE_MINUS_SRC_ALPHA)
          Gl.glEnable(Gl::GL_SCISSOR_TEST)
          Gl.glScissor(
            region.x * scale_factor,
            (@frame.height - region.bottom) * scale_factor,
            region.width * scale_factor,
            region.height * scale_factor
            )

          Gl.glClearColor(*@background)
          Gl.glClear(Gl::GL_COLOR_BUFFER_BIT)

          @driver.clear

          self.draw(@driver)
          self.draw_subviews(@driver)

          @driver.draw_stages

          Gl.glDisable(Gl::GL_SCISSOR_TEST)
        end # !region.empty?

      end # program.use

      window.swap_buffers
    end # bind_context(window)
  end

end # Window

end # GUI
