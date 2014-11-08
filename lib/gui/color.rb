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
#  color.rb
#    Color class


require 'snow-math'


module GUI

# Color is just a Vec4 with additions for setting/getting RGBA/HSVA.
class Color < ::Snow::Vec4

  ONE_OVER_SIX = 1.0 / 6.0

  alias_method :r, :x
  alias_method :r=, :x=
  alias_method :g, :y
  alias_method :g=, :y=
  alias_method :b, :z
  alias_method :b=, :z=
  alias_method :a, :w
  alias_method :a=, :w=

  class << self
    # hue, sat, and value are expected to be in the range of 0.0 to 1.0.
    # Components outside this range may result in incorrect results.
    def from_hsv(hue, sat, value, alpha = 1.0, out = nil)
      out ||= new

      hue *= 6.0

      if sat < ::Snow.float_epsilon
        return out.set(value, value, value, alpha)
      end

      face = hue.floor
      hue -= face
      beta = value * (1.0 - sat)

      case face % 6
      when 0
        out.set(value, value * (1.0 - sat * (1.0 - hue)), beta, alpha)
      when 1
        out.set(value * (1.0 - hue * sat), value, beta, alpha)
      when 2
        out.set(beta, value, value * (1.0 - sat * (1.0 - hue)), alpha)
      when 3
        out.set(beta, value * (1.0 - hue * sat), value, alpha)
      when 4
        out.set(value * (1.0 - sat * (1.0 - hue)), beta, value, alpha)
      when 5
        out.set(value, beta, value * (1.0 - hue * sat), alpha)
      end
    end

    def red ;        new(1.0, 0.0, 0.0, 1.0) ; end
    def green ;      new(1.0, 0.0, 0.0, 1.0) ; end
    def blue ;       new(1.0, 0.0, 0.0, 1.0) ; end
    def white ;      new(1.0, 1.0, 1.0, 1.0) ; end
    def near_white ; new(0.95, 0.95, 0.95, 1.0) ; end
    def light_grey ; new(0.8, 0.8, 0.8, 1.0) ; end
    def grey ;       new(0.5, 0.5, 0.5, 1.0) ; end
    def dark_grey ;  new(0.2, 0.2, 0.2, 1.0) ; end
    def near_black ; new(0.05, 0.05, 0.05, 1.0) ; end
    def black ;      new(0.0, 0.0, 0.0, 1.0) ; end
  end

  # Assumes self's values are RGB.
  def to_hsv(out = nil)
    out = clamped(out)
    ir = out.r
    ig = out.g
    ib = out.b

    lower = (ir < ig ? ir : ig)
    lower = lower < ib ? lower : ib

    upper = (ir > ig ? ir : ig)
    upper = upper > ib ? upper : ib

    chroma = upper - lower

    if chroma < 0.0
      out.x = 0.0
      out.y = 0.0
    else
      if upper == ir
        proposed = ((ig - ib) / chroma) * ONE_OVER_SIX
        if proposed < 0.0
          out.x = proposed + 1.0
        else
          out.x = proposed
        end
      elsif upper == ig
        out.x = (2.0 + (ib - ir) / chroma) * ONE_OVER_SIX
      else
        out.x = (4.0 + (ir - ig) / chroma) * ONE_OVER_SIX
      end

      out.y = chroma / upper
    end

    out.z = upper

    out
  end

  def clamped(out = nil)
    out ||= self.class.new
    out.set(
      if self.x < 0.0 ; 0.0 ; elsif self.x > 1.0 ; 1.0 ; else ; self.x ; end,
      if self.y < 0.0 ; 0.0 ; elsif self.y > 1.0 ; 1.0 ; else ; self.y ; end,
      if self.z < 0.0 ; 0.0 ; elsif self.z > 1.0 ; 1.0 ; else ; self.z ; end,
      if self.w < 0.0 ; 0.0 ; elsif self.w > 1.0 ; 1.0 ; else ; self.w ; end
      )
  end

  def clamp!
    clamped(self)
  end

  def to_i
    bx = (self.x * 255.0).to_i & 0xFF
    by = (self.y * 255.0).to_i & 0xFF
    bz = (self.z * 255.0).to_i & 0xFF
    bw = (self.w * 255.0).to_i & 0xFF
    (((((bw << 8) | bz) << 8) | by) << 8) | bx
  end

end

end

