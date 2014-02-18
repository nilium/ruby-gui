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
#  button.rb
#    Basic button widget


require 'gui/view'
require 'gui/driver'
require 'gui/event'


module GUI


class Button < View

  attr_accessor :on_click_block

  def initialize(frame = nil)
    super

    @down = false
  end

  def on_click(&block)
    self.on_click_block = block
  end

  def handle_event(event)
    case event.kind
    when :mouse_button
      action_button = event.button == 0
      if action_button
        pos = convert_from_root(event.position.dup)
        case event.action
        when Glfw::PRESS
          if bounds.include?(pos)
            event.stop_propagation!
            redirect_events(:mouse_button, self)
            @down = true
          end

        when Glfw::RELEASE
          if @down
            event.stop_propagation!
            redirect_events(:mouse_button, nil)
            @down = false
            if bounds.include?(pos) && on_click_block
              on_click_block[self]
            end
          end
        end
      end

    else super
    end
  end

  def draw(driver)
  end

end


end
