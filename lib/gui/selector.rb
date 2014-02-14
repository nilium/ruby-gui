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
#  selector.rb
#    Selector chain class.


module GUI

class Selector

  class << self
    def view_matches_attr(view, name, value)
      view.respond_to?(name) && view.__send__(name) == value
    end

    def build(selector_str)

    end
  end # singleton_class

  # The next
  attr_accessor :succ
  # Array of proc/lambda objects that receive a view and return true if
  # the view matches, otherwise nil/false
  attr_accessor :attributes
  attr_accessor :direct

  def initialize
    @succ = nil
    @attributes = []
    @direct = false
  end

  # Whether this selector matches a view.
  def matches?(view)
    attributes.empty? || attributes.all? { |sel_attr| sel_attr[view] }
  end

  def find_match(view)
    # TODO: Grab leaves and test selectors in reverse order
    further = direct ? nil : self
    if matches?(view)
      return view unless @succ
      further = @succ
    end

    view.subviews.detect { |subview| further.find_match(subview) }
  end

end # Selector

end # GUI
