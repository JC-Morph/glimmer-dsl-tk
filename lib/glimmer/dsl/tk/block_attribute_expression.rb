# Copyright (c) 2020-2021 Andy Maleh
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'glimmer/dsl/expression'

module Glimmer
  module DSL
    module Tk
      class BlockAttributeExpression < Expression
        def can_interpret?(parent, keyword, *args, &block)
          block_given? and
            args.size == 0 and
            (parent.respond_to?("#{keyword}_block=") || (parent.respond_to?(:tk) && parent.tk.respond_to?(keyword)))
        end
  
        def interpret(parent, keyword, *args, &block)
          if parent.respond_to?("#{keyword}_block=")
            parent.send("#{keyword}_block=", block)
          else
            parent.tk.send(keyword, block)
          end
          nil
        end
      end
    end
  end
end
