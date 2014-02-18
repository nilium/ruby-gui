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
#  event_dispatch.rb
#    Event dispatch module


require 'set'
require 'gui/event'


module GUI

module EventDispatch

  def dispatch_event_upwards(event, target, visited, &provider)
    raise ArgumentError, "No target-provider block given" unless block_given?
    return unless event.propagating? && target
    dispatch_event_with_target(event, visited) do
      target = provider[target]
    end
  end

  def redirect_events(kind, to_target)
    redirects = (@event_redirects ||= {})
    if to_target.nil? && redirects.include?(kind)
      redirects.delete(kind)
    else
      redirects[kind] = to_target
    end

    self
  end

  def post_event(event)
    (@events ||= []) << event
    self
  end

  def dispatch_event_to_target(target, event, visited)
    return unless event.propagating? &&
                  target &&
                  !visited.include?(target.__id__)

    if target.respond_to?(:handle_event)
      target.handle_event(event)
    end

    visited << target.__id__

    self
  end

  def dispatch_event_with_target(event, visited, once: false, parent_msg: :superview, &provider)
    raise ArgumentError, "No target-provider block given" unless block_given?

    last_target = nil
    target = yield

    begin
      dispatch_event_to_target(target, event, visited)
      last_target = target
      target = yield
    end while !once && event.propagating? && target.__id__ != last_target.__id__

    dispatch_event_upwards(event, target, visited) do |above|
      above && above.respond_to?(parent_msg) && above.__send__(parent_msg)
    end

    self
  end

  def dispatch_events(parent_msg = nil)
    return self unless @events
    parent_msg ||= :superview

    visited = Set.new
    redirects = (@event_redirects ||= {})

    @events.each do |event|
      kind = event.kind
      visited.clear

      if redirects.include?(kind)
        dispatch_event_with_target(event, visited, parent_msg: parent_msg) do
          redirects[kind]
        end

        next unless event.propagating?
      end

      dispatch_event_with_target(event, visited, parent_msg: parent_msg) do
        event.target
      end

      next unless event.propagating?

      # If the event is still propagating, send it to all the leaf views and
      # their superviews next.
      leaf_views.each do |leaf|
        view = leaf.view
        dispatch_event_with_target(event, visited, once: true, parent_msg: parent_msg) do
          view
        end
        break unless event.propagating?
      end
    end.clear

    self
  end

end # EventDispatch

end # GUI
