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
#  checks.rb
#    Selector checks (class/tag/attribute)


module GUI

#
# All selector checks (held by the attributes array of a selector) expect a
# call(view) method to be implemented. This returns either true or false values,
# though it's only necessary that they return things that evaluate to true or
# false. It is possible, therefore, to hand-write all your selectors rather than
# compiling them, which can be _much_ faster when performing lookups since
# attribute checks don't have to depend on reducing something by sending
# messages over and over.
#
# In practice, however, selectors are just slow in all my tests right now and I
# need to rewrite them to test starting with leaf views anyway (this should
# result in more specific matches and avoid recursive tests since it's then
# possible to iterate down through parents and cut off if a minimum depth isn't
# met [i.e., a selector with N views to match requires at least depth N, but
# can match views across depths greater than N if it has indirect matches]).
#


class ViewTagCheck

  def initialize(tagname)
    @tagname = tagname
  end

  def call(view)
    view.tag == tagname
  end

  alias_method :[], :call

end # ViewTagCheck


class ViewClassCheck

  def initialize(classname)
    @classnames =
      case classname
      when Array then classname.dup
      when Symbol then [classname]
      when String then [classname.to_sym]
      else raise ArgumentError, "Invalid class name type: #{classname.class}"
      end
  end

  def call(view)
    klass = view.class
    name = nil
    while klass
      name = ViewAttrCheck.extract_class_name(klass)
      return true if @classnames.include?(name)
      klass = klass.superclass
    end
    false
  end

  alias_method :[], :call

end # ViewClassCheck


class ViewAttrCheck

  SCO_MARKER          = '::'
  KEYPATH_SEPARATOR   = '.'

  class << self
    attr_accessor :__module_name_cache__

    def extract_class_name(klass)
      (__module_name_cache__ ||= {})[klass] ||= begin
        # Cache classname symbols because string ops are slow
        name = klass.name
        sco_index = klass.rindex(SCO_MARKER)
        if sco_index
          klass.slice!(0 .. sco_index + 1)
        end
        name.to_sym
      end
    end
  end # singleton_class

  def initialize(key, operator, operand)
    @key = key.split(KEYPATH_SEPARATOR).map!(&:to_sym)
    @operator = operator
    @operand = operand
    @is_string = @operand.kind_of?(String)
  end

  # NOTE: Deprecate and remove class checks for ViewAttrCheck? Might be a good
  # idea, but it sort of remains since it's occasionally handy to do something
  # like [content_view.class = Something]. Probably just going to remove this,
  # though.
  def class_check(klass)
    # Cache Symbol for operand so I'm not converting it every time.
    name = (@operand_sym ||= @operand.to_sym)

    while klass
      case @operator
      when :equal
        return true if self.class.extract_class_name(klass) == name
      when :not_equal
        return true unless self.class.extract_class_name(klass) == name
      when :trueish # Necessarily true for classes.
        true
      else # Otherwise no test passes.
        false
      end
      klass = klass.superclass
    end
    false
  end

  def call(view)
    view_value = @key.reduce(view) { |value, msg| value.__send__(msg) }

    if @is_string && !view_value.kind_of?(String)
      view_value =
        case view_value
        when Class then return class_check(view_value) # return early
        when Module then extract_class_name(view_value)
        when Enumerable then
          # There is a case here where doing something like
          # `included_modules <- X` will fail because the values contained by
          # the Enumerable are modules but the check won't know, so it'll just
          # always fail. Thought about working around this by mapping modules
          # to their extracted names, but decided I'll only do that if it turns
          # out to be a problem.
          return false unless @operator == :contains
          view_value
        else view_value.to_s
        end
    end

    case operator
    when :trueish       then !!view_value
    when :falseish      then !view_value
    when :equal         then view_value == @operand
    when :not_equal     then view_value != @operand
    when :greater       then view_value >  @operand
    when :greater_equal then view_value >= @operand
    when :lesser        then view_value <  @operand
    when :lesser_equal  then view_value <= @operand
    when :contains
      view_value.respond_to?(:include?) && view_value.include?(@operand)
    else
      raise SelectorError, "Invalid operator for ViewAttrCheck: #{operator}"
    end
  end

  alias_method :[], :call

end # ViewAttrCheck

end # GUI

