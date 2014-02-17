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
#  view.rb
#    Base class for view types.


require 'gui/geom'


module GUI

class View

  ViewDepth = Struct.new(:view, :depth)
  ViewDepth::SORT_PROC = -> (l, r) { -(l.depth <=> r.depth) }

  # View tag (default: nil)
  attr_accessor :tag

  # Subviews held by the view. Should not be modified directly. Instead, to
  # add a subview, use add_view.
  attr_reader   :subviews

  # Rectangular portion
  attr_accessor :frame # Rect

  def initialize(frame = nil)
    @leaf_cache     = nil
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

  def scale_factor
    window.scale_factor
  end

  def views_containing_point(point, out: nil)
    out ||= []

    if bounds.include?(point)
      out.unshift self

      converted_point = Vec2.new
      @subviews.each do |view|
        point.copy(converted_point)
        converted_point.add!(view.frame.origin)
        view.views_containing_point(converted_point, out: out)
      end
    end

    out
  end

  def convert_to_root(point, out = nil)
    out ||= point.copy
    below = self
    while below.superview
      out.subtract!(below.frame.origin)
      below = below.superview
    end
    out
  end

  def convert_from_root(point, out = nil)
    out ||= point.copy
    below = self
    while below.superview
      out.add!(below.frame.origin)
      below = below.superview
    end
    out
  end

  def handle_event(event)
  end

  def window
    above = self
    above = above.superview while above.superview && !above.kind_of?(Window)
    above
  end

  def root_view
    above = self
    above = above.superview while above.superview
    above
  end

  def each_superview
    if block_given?
      above = superview
      while above
        yield(above)
        above = above.superview
      end
      self
    else
      to_enum(:each_superview)
    end
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
      old_superview.__invalidate_leaf_caches__
      old_superview.subviews.delete(self)
      old_superview.invalidate(@frame)
      old_superview.request_layout
    end

    @superview = new_superview
    if !new_superview.nil?
      new_superview.subviews << self
      new_superview.__invalidate_leaf_caches__
      new_superview.invalidate(@frame)
      new_superview.request_layout
    end
  end

  def __invalidate_leaf_caches__
    @leaf_cache = nil
    superview.__invalidate_leaf_caches__ if superview
  end

  def leaf_views(__out: nil, __depth: nil, __cache: true)
    if @leaf_cache
      __out += @leaf_cache if __out.__id__ != @leaf_cache.__id__
      return @leaf_cache
    end

    __out   ||= []
    __depth ||= 0

    if @subviews.empty?
      __out << ViewDepth[self, __depth]
    else
      @subviews.each do |view|
        view.leaf_views(__out: __out, __depth: __depth + 1, __cache: false)
      end
    end

    __out.uniq!
    __out.sort!(&ViewDepth::SORT_PROC)

    @leaf_cache = __out if __cache

    __out
  end

  def add_view(view)
    raise ArgumentError, "View already has a superview" if view.superview
    view.superview = self
    __invalidate_leaf_caches__
    self
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
    end
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
