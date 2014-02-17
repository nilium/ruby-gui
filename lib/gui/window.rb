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


  attr_accessor :background

  def initialize(frame, title, context = nil)
    context ||= Context.__active_context__

    @title = title
    @background = Color.dark_grey
    @in_update = []
    @context = context
    @events = []
    @event_redirects = {}

    super(frame)

    __window__
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

  def handle_event(event)
    super
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

          # draw_subviews (those within region)

          Gl.glDisable(Gl::GL_SCISSOR_TEST)
        end # !region.empty?

      end # program.use

      window.swap_buffers
    end # bind_context(window)
  end


  # Event dispatch

  def __post_event__(event)
    event.target = @event_redirects[event.kind] || event.target
    @events << event
  end

  def __dispatch_event_upwards__(event, target, tested_views)
    return unless event.propagating?

    above = target && target.respond_to?(:superview) && target.superview

    while event.propagating? && above
      if above.respond_to?(:handle_event) && !tested_views.include?(above.__id__)
        tested_views << above.__id__
        above.handle_event(event)
      end

      above = above.respond_to?(:superview) && above.superview
    end
  end

  def __dispatch_events__
    @events.each do |event|
      tested_views = Set.new

      begin
        target = event.target

        unless tested_views.include?(target.__id__)
          if target && target.respond_to?(:handle_event)
            target.handle_event(event)
            tested_views << target.__id__
          end

          break unless event.propagating?
        end
      end until target.__id__ == event.target.__id__

      __dispatch_event_upwards__(event, target, tested_views)

      next if event.target || !event.propagating?

      # If the event is still propagating, send it to all the leaf views and
      # their superviews next.
      leaf_views.each do |leaf|
        view = leaf.view
        next if tested_views.include?(view.__id__)

        if view.respond_to?(:handle_event)
          tested_views << view.__id__
          view.handle_event(event)
        end

        break unless event.propagating?

        __dispatch_event_upwards__(event, view, tested_views)
      end
    end.clear
  end

end # Window

end # GUI
