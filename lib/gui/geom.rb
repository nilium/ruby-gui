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
#  geom.rb
#    Geometric types


require 'snow-math'


module GUI

Vec3 = Snow::Vec3
Vec4 = Snow::Vec4
Quat = Snow::Quat
Mat3 = Snow::Mat3
Mat4 = Snow::Mat4

class Vec2 < Snow::Vec2

  def min(other, out = nil)
    out ||= self.class.new
    out.set(
      other.x < self.x ? other.x : self.x,
      other.y < self.y ? other.y : self.y
    )
  end

  def max(other, out = nil)
    out ||= self.class.new
    out.set(
      other.x > self.x ? other.x : self.x,
      other.y > self.y ? other.y : self.y
    )
  end

  def min!(other)
    min(other, self)
  end

  def max!(other)
    max(other, self)
  end

  def minmax(other)
    [min(other), max(other)]
  end

end # Vec2


# 2D rectangle. Positive X is to the right, positive Y is up. Origin mark
# the rectangle's top-left corner.
class Rect
  attr_reader :origin, :size # Vec2

  def initialize(*args)
    case args.length
    when 0
      @origin = Vec2[0, 0]
      @size = Vec2[0, 0]
    when 1
      @origin = args[0].origin.dup
      @size = args[0].size.dup
    when 2
      @origin = args[0].dup
      @size = args[1].dup
    when 4
      @origin = Vec2[args[0], args[1]]
      @size = Vec2[args[2], args[3]]
    else
      raise ArgumentError, "Invalid arguments to #{self.class}.new"
    end
  end

  def dup
    self.class.new(@origin.dup, @size.dup)
  end

  class << self ; alias_method :[], :new ; end

  # Edge methods
  def left
    @origin.x
  end

  def left=(value)
    @origin.x = value
  end

  def right
    @origin.x + @size.x
  end

  def right=(value)
    @size.x = value - @origin.x
  end

  def top
    @origin.y
  end

  def top=(value)
    @origin.y = value
  end

  def bottom
    @origin.y + @size.y
  end

  def bottom=(value)
    @size.y = value - @origin.y
  end

  # Wrappers for size
  def width
    @size.x
  end

  def width=(value)
    @size.x = value
  end

  def height
    @size.y
  end

  def height=(value)
    @size.y = value
  end

  # Wrappers for origin
  def x
    @origin.x
  end

  def x=(value)
    @origin.x = value
  end

  def y
    @origin.y
  end

  def y=(value)
    @origin.y = value
  end

  def with_origin(x, y, out = nil)
    out ||= Rect.new
    out.set(x || @origin.x, y || @origin.y, @size.x, @size.y)
  end

  def with_size(x, y, out = nil)
    out ||= Rect.new
    out.set(@origin.x, @origin.y, x || @size.x, y || @size.y)
  end

  def intersects?(other)
    !(
      left > other.right ||
      right < other.left ||
      top > other.bottom ||
      bottom < other.top
    )
  end

  # The result for this is only valid if intersects? returns true. It does
  # not attempt to test whether an intersection actually occurs.
  def intersection(other, out = nil)
    out ||= self.class.new
    max_top = [top, other.top].max
    max_left = [left, other.left].max
    out.set(
      max_left,
      max_top,
      [right, other.right].min - max_left,
      [bottom, other.bottom].min - max_top
    )
  end

  def intersection!(other, out = nil)
    intersection(other, self)
  end

  def contains_both(other, out = nil)
    out ||= self.class.new
    min_top = [top, other.top].min
    min_left = [left, other.left].min
    out.set(
      min_left,
      min_top,
      [right, other.right].max - min_left,
      [bottom, other.bottom].max - min_top
    )
  end

  def contains_both!(other)
    contains_both(other, self)
  end

  def set(x, y, width, height)
    @origin.x = x
    @origin.y = y
    @size.x = width
    @size.y = height
    self
  end

  def empty?
    @size.x <= Snow::float_epsilon &&
    @size.y <= Snow::float_epsilon
  end

  def to_s
    "(rect #{@origin.x} #{@origin.y} #{@size.x} #{@size.y})"
  end

end # Rect

end # GUI
