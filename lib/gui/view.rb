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
#  widget.rb
#    Base class for view types.


require 'gui/geom'


module GUI

class View

  # View tag (default: nil)
  attr_accessor :tag

  # Subviews held by the view. Should not be modified directly. Instead, to
  # add a subview, use add_view.
  attr_reader   :subviews

  # Rectangular portion
  attr_accessor :frame # Rect

  def initialize(frame = nil)
    @needs_layout   = false
    @invalidated    = nil
    @subviews       = []
    @attributes     = []
    @superview      = nil
    @tag            = nil
    @frame          = frame || Rect.new

    invalidate
    request_layout
  end

  # Returns the containing superview of the view.
  def superview
    @superview
  end

  # Sets the containing superview of the view. This invalidates and requests
  # layout on the previous superview, if any.
  def superview=(new_superview)
    old_superview = @superview
    if !old_superview.nil?
      old_superview.delete(self)
      old_superview.invalidate(@frame.dup)
      old_superview.request_layout
    end

    @superview = new_superview
    if !new_superview.nil?
      new_superview.children << self
    end
  end

  def add_view(view)
    raise ArgumentError, "View already has a superview" if view.superview
    view.superview = self
  end

  def bounds
    @frame.with_origin(0, 0)
  end

  def remove_from_superview
    self.superview = nil
  end

  def invalidated_region
    @invalidated
  end

  def invalidate(region = nil)
    if @invalidated
      @invalidated.contains_both!(region || @frame)
    else
      @invalidated = (region || @frame.with_origin(0, 0)).dup
    end.intersection!(bounds)

    self
  end

  def request_layout
    @needs_layout = true
  end

  def needs_layout?
    @needs_layout
  end

  def perform_layout
  end

  def view_with_tag(tag)
    if @tag == tag
      self
    else
      @subviews.detect { |subview| subview.view_with_tag(tag) }
    end
  end

  def view_with_selector(selector)
    nil
  end

  def draw_subviews
    @subviews.each do |subview|
      # push relevant state
      subview.draw
      # pop relevant state
    done
  end

  def [](selector)
    case selector
    when Symbol   then view_with_tag(selector)
    when Selector then view_with_selector(selector)
    when String   then view_with_selector(Selector.build(selector))
    when Numeric  then @subviews[selector]
    else raise ArgumentError, "Invalid selector for View#[]"
    end
  end

end # View

end # GUI
