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
#  event.rb
#    Basic event class


module GUI

class EventCancellationError < StandardError ; end

class Event

  __Target__ = Struct.new(:p)

  attr_reader   :sender
  attr_reader   :kind
  attr_reader   :info
  attr_accessor :target

  class << self ; alias_method :[], :new ; end

  def initialize(sender, kind, **info)
    @sender = sender
    @kind = kind
    @info = info.freeze
    @cancelled = false
    @propagating = true
    @target = info[:target]
  end

  def method_missing(meth, *args)
    if info.include?(meth) && args.empty?
      info[meth]
    else
      raise NoMethodError, "No such method #{meth}"
    end
  end

  def original_target
    info[:target]
  end

  def cancellable?
    true
  end

  def cancelled?
    @cancelled
  end

  def propagating?
    @propagating
  end

  def stop_propagation!
    @propagating = false
    self
  end

  def cancel!
    if cancellable?
      @cancelled = true
    else
      raise EventCancellationError, "Unable to cancel event"
    end
    self
  end

  def to_s
    "(event (sender #{sender}) (kind #{kind})#{
      ' ' unless @info.empty?
      }#{
      @info.map { |k,v| "(#{k} #{v})"}.join ' '
      })"
  end

end # Event

end # GUI

