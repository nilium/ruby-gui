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
    @window_cache   = nil
    @rootview_cache = nil

    invalidate
    request_layout
  end

  # Recursively called for subviews to invalidate their caches as well.
  def __invalidate_ascendant_view_caches__
    @window_cache = nil
    @rootview_cache = nil
    @subviews.each(&:__invalidate_ascendant_view_caches__)
    self
  end

  def invalidate_caches
    __invalidate_leaf_caches__
    __invalidate_ascendant_view_caches__
    self
  end

  def redirect_events(kind, to_target)
    window.redirect_events(kind, to_target)
  end

  def post_event(event)
    window.post_event
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
    above = self
    while above.superview
      out.add!(above.frame.origin)
      above = above.superview
    end
    out
  end

  def convert_from_root(point, out = nil)
    out ||= point.copy
    above = self
    while above.superview
      out.subtract!(above.frame.origin)
      above = above.superview
    end
    out
  end

  #
  # Handles an event. By default, this is not implemented, as container views
  # (i.e., basic View instances) do not require event handling and can save
  # time by simply not responding to handle_event at all.
  #
  # If a view subclass does not require handle_event, do not implement it --
  # it's faster than having an empty handle_event.
  #
  # def handle_event(event)
  # end

  def window
    @window_cache ||= begin
      above = self
      above = above.superview while above.superview && !above.kind_of?(Window)
      above if above.kind_of?(Window)
    end
  end

  def root_view
    @rootview_cache ||= begin
      above = self
      above = above.superview while above.superview
      above
    end
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
    self.__invalidate_leaf_caches__

    old_superview = @superview
    if !old_superview.nil?
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

    __invalidate_ascendant_view_caches__

    new_superview
  end

  def __invalidate_leaf_caches__
    @leaf_cache = nil
    each_superview(&:__invalidate_leaf_caches__)
  end

  # If cache is true, the results will be cached leaf views relative to this
  # view, but only if the output and depth arguments are nil.
  def leaf_views(__out: nil, __depth: nil, cache: true)
    return @leaf_cache if @leaf_cache && cache && !__out && !__depth

    __out   ||= []
    __depth ||= 0

    if @subviews.empty?
      __out << ViewDepth[self, __depth]
    else
      @subviews.each do |view|
        view.leaf_views(__out: __out, __depth: __depth + 1, cache: false)
      end
    end

    __out.uniq!
    __out.sort!(&ViewDepth::SORT_PROC)

    @leaf_cache = __out if cache

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

  #
  # Invalidates layout on self and all subviews thereof. Any subview will have
  # its perform_layout method called in turn.
  #
  def request_layout
    if !@needs_layout
      @needs_layout = true
      subviews.each(&:request_layout)
    end
  end

  def needs_layout?
    @needs_layout
  end

  #
  # For view subclasses or views with extended layout features, this should
  # layout its subviews (ideally within the bounds of self, but this isn't
  # required). By default, all it does is call its subviews' perform_layout
  # functions.
  #
  # Implementations should either call their superclass's perform_layout to
  # initiate layout of subviews or do so themselves.
  #
  def perform_layout
    @needs_layout = false
    @subviews.each(&:perform_layout)
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

  #
  # Drawing routine for a view, given a graphics driver.
  #
  # Views, by default, do not implement this and as such calling this as a
  # super method in subclasses has no effect. Views should only implement this
  # if they intend to draw something, otherwise they should opt for not
  # providing an implementation.
  #
  # Subclasses of views with drawing routines should call super as needed,
  # though it may be advisable to check if it can be called and whether you
  # want to call it in the first place (i.e., is it in addition to drawing or
  # replacing all drawing?).
  #
  # def draw(driver)
  # end

  def draw_subviews(driver)
    @subviews.each do |subview|
      driver.push_state do
        driver.origin += subview.frame.origin
        # push relevant state
        if subview.respond_to?(:draw)
          subview.draw(driver)
        end
        subview.draw_subviews(driver)
        # pop relevant state
      end
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
