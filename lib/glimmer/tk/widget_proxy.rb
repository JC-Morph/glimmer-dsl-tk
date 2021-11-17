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

require 'glimmer/data_binding/tk/one_time_observer'

module Glimmer
  module Tk
    # Proxy for Tk Widget objects
    #
    # Follows the Proxy Design Pattern
    class WidgetProxy
      class << self
        def create(keyword, parent, args, &block)
          widget_proxy_class(keyword).new(keyword, parent, args, &block)
        end
        
        def widget_proxy_class(keyword)
          begin
            class_name = "#{keyword.camelcase(:upper)}Proxy".to_sym
            Glimmer::Tk.const_get(class_name)
          rescue => e
            Glimmer::Config.logger.debug {"Unable to instantiate custom class name for #{keyword} ... defaulting to Glimmer::Tk::WidgetProxy"}
            Glimmer::Config.logger.debug {e.full_message}
            Glimmer::Tk::WidgetProxy
          end
        end
        
        # This supports widgets in and out of basic Tk
        def tk_widget_class_for(underscored_widget_name)
          tk_widget_class_basename = underscored_widget_name.camelcase(:upper)
          # TODO consider exposing this via Glimmer::Config
          potential_tk_widget_class_names = [
            "::Tk::Tile::#{tk_widget_class_basename}",
            "::Tk#{tk_widget_class_basename}",
            "::Tk::#{tk_widget_class_basename}",
            "::Tk::BWidget::#{tk_widget_class_basename}",
            "::Tk::Iwidgets::#{tk_widget_class_basename}",
            "::Glimmer::Tk::#{tk_widget_class_basename}Proxy",
          ]
          tk_widget_class = nil
          potential_tk_widget_class_names.each do |tk_widget_name|
            begin
              tk_widget_class = eval(tk_widget_name)
              break
            rescue RuntimeError, SyntaxError, NameError => e
              Glimmer::Config.logger.debug {e.full_message}
            end
          end
          tk_widget_class if tk_widget_class.respond_to?(:new)
        end
      end
      
      FONTS_PREDEFINED = %w[default text fixed menu heading caption small_caption icon tooltip]
      
      attr_reader :parent_proxy, :tk, :args, :keyword, :children

      # Initializes a new Tk Widget
      #
      # Styles is a comma separate list of symbols representing Tk styles in lower case
      def initialize(underscored_widget_name, parent_proxy, args, &block)
        @parent_proxy = parent_proxy
        @args = args
        @keyword = underscored_widget_name
        @block = block
        build_widget
        # a common widget initializer
        @parent_proxy&.post_initialize_child(self)
        initialize_defaults
        post_add_content if @block.nil?
      end
      
      def root_parent_proxy
        current = self
        current = current.parent_proxy while current.parent_proxy
        current
      end
      
      def toplevel_parent_proxy
        ancestor_proxies.find {|widget_proxy| widget_proxy.is_a?(ToplevelProxy)}
      end
      
      # returns list of ancestors ordered from direct parent to root parent
      def ancestor_proxies
        ancestors = []
        current = self
        while current.parent_proxy
          ancestors << current.parent_proxy
          current = current.parent_proxy
        end
        ancestors
      end
      
      def children
        @children ||= []
      end
      
      # Subclasses may override to perform post initialization work on an added child
      def post_initialize_child(child)
        children << child
      end

      # Subclasses may override to perform post add_content work
      def post_add_content
        # No Op by default
      end

      def self.widget_exists?(underscored_widget_name)
        !!tk_widget_class_for(underscored_widget_name) || (Glimmer::Tk.constants.include?("#{underscored_widget_name.camelcase(:upper)}Proxy".to_sym) && Glimmer::Tk.const_get("#{underscored_widget_name.camelcase(:upper)}Proxy".to_sym).respond_to?(:new))
      end

      def tk_widget_has_attribute_setter?(attribute)
        return true if @tk.respond_to?(attribute) && attribute != 'focus' # TODO configure exceptions via constant if needed
        result = nil
        begin
          # TK Widget currently doesn't support respond_to? properly, so I have to resort to this trick for now
          @tk.send(attribute_setter(attribute), @tk.send(attribute))
          result = true
        rescue => e
          Glimmer::Config.logger.debug { "No tk attribute setter for #{attribute}" }
          Glimmer::Config.logger.debug { e.full_message }
          result = false
        end
        result
      end
      
      def tk_widget_has_attribute_getter_setter?(attribute)
        begin
          # TK Widget currently doesn't support respond_to? properly, so I have to resort to this trick for now
          @tk.send(attribute)
          true
        rescue => e
          Glimmer::Config.logger.debug { "No tk attribute getter setter for #{attribute}" }
          false
        end
      end
      
      def has_state?(attribute)
        attribute = attribute.sub(/\?$/, '').sub(/=$/, '')
        if @tk.respond_to?(:tile_state)
          begin
            @tk.tile_instate(attribute)
            true
          rescue => e
            Glimmer::Config.logger.debug { "No tk state for #{attribute}" }
            false
          end
        else
          false
        end
      end
      
      def has_attributes_attribute?(attribute)
        attribute = attribute.sub(/\?$/, '').sub(/=$/, '')
        @tk.respond_to?(:attributes) && @tk.attributes.keys.include?(attribute.to_s)
      end
      
      def has_attribute?(attribute, *args)
        (widget_custom_attribute_mapping[tk.class] and widget_custom_attribute_mapping[tk.class][attribute.to_s]) or
          tk_widget_has_attribute_setter?(attribute) or
          tk_widget_has_attribute_getter_setter?(attribute) or
          has_state?(attribute) or
          has_attributes_attribute?(attribute) or
          respond_to?(attribute_setter(attribute), args) or
          respond_to?(attribute_setter(attribute), *args, super_only: true) or
          respond_to?(attribute, *args, super_only: true)
      end

      def set_attribute(attribute, *args)
        begin
          widget_custom_attribute = widget_custom_attribute_mapping[tk.class] && widget_custom_attribute_mapping[tk.class][attribute.to_s]
          if respond_to?(attribute_setter(attribute), super_only: true)
            send(attribute_setter(attribute), *args)
          elsif respond_to?(attribute, super_only: true) && self.class.instance_method(attribute).parameters.size > 0
            send(attribute, *args)
          elsif widget_custom_attribute
            widget_custom_attribute[:setter][:invoker].call(@tk, args)
          elsif tk_widget_has_attribute_setter?(attribute)
            unless args.size == 1 && @tk.send(attribute) == args.first
              if args.size == 1
                @tk.send(attribute_setter(attribute), *args)
              else
                @tk.send(attribute_setter(attribute), args)
              end
            end
          elsif tk_widget_has_attribute_getter_setter?(attribute)
            @tk.send(attribute, *args)
          elsif has_state?(attribute)
            attribute = attribute.sub(/=$/, '')
            if !!args.first
              @tk.tile_state(attribute)
            else
              @tk.tile_state("!#{attribute}")
            end
          elsif has_attributes_attribute?(attribute)
            attribute = attribute.sub(/=$/, '')
            @tk.attributes(attribute, args.first)
          else
            raise "#{self} cannot handle attribute #{attribute} with args #{args.inspect}"
          end
        rescue => e
          Glimmer::Config.logger.error {"Failed to set attribute #{attribute} with args #{args.inspect}. Attempting to set through style instead..."}
          Glimmer::Config.logger.error {e.full_message}
          apply_style(attribute => args.first)
        end
      end

      def get_attribute(attribute)
        widget_custom_attribute = widget_custom_attribute_mapping[tk.class] && widget_custom_attribute_mapping[tk.class][attribute.to_s]
        if respond_to?(attribute, super_only: true)
          send(attribute)
        elsif widget_custom_attribute
          widget_custom_attribute[:getter][:invoker].call(@tk, args)
        elsif tk_widget_has_attribute_getter_setter?(attribute)
          @tk.send(attribute)
        elsif has_state?(attribute)
          @tk.tile_instate(attribute.sub(/\?$/, ''))
        elsif has_attributes_attribute?(attribute)
          result = @tk.attributes[attribute.sub(/\?$/, '')]
          result = result == 1 if result.is_a?(Integer)
          result
        else
          send(attribute)
        end
      end

      def attribute_setter(attribute)
        "#{attribute}="
      end
      
      def style=(styles)
        styles.each do |attribute, value|
          apply_style(attribute => value)
        end
      end
      
      def grid(options = {})
        options = options.stringify_keys
        options['rowspan'] = options.delete('row_span') if options.keys.include?('row_span')
        options['columnspan'] = options.delete('column_span') if options.keys.include?('column_span')
        options['rowweight'] = options.delete('row_weight') if options.keys.include?('row_weight')
        options['columnweight'] = options.delete('column_weight') if options.keys.include?('column_weight')
        options['columnweight'] = options['rowweight'] = options.delete('weight')  if options.keys.include?('weight')
        options['rowminsize'] = options.delete('row_minsize') if options.keys.include?('row_minsize')
        options['rowminsize'] = options.delete('minheight') if options.keys.include?('minheight')
        options['rowminsize'] = options.delete('min_height') if options.keys.include?('min_height')
        options['columnminsize'] = options.delete('column_minsize') if options.keys.include?('column_minsize')
        options['columnminsize'] = options.delete('minwidth') if options.keys.include?('minwidth')
        options['columnminsize'] = options.delete('min_width') if options.keys.include?('min_width')
        options['columnminsize'] = options['rowminsize'] = options.delete('minsize')  if options.keys.include?('minsize')
        index_in_parent = griddable_parent_proxy&.children&.index(griddable_proxy)
        if index_in_parent
          TkGrid.rowconfigure(griddable_parent_proxy.tk, index_in_parent, 'weight'=> options.delete('rowweight')) if options.keys.include?('rowweight')
          TkGrid.rowconfigure(griddable_parent_proxy.tk, index_in_parent, 'minsize'=> options.delete('rowminsize')) if options.keys.include?('rowminsize')
          TkGrid.columnconfigure(griddable_parent_proxy.tk, index_in_parent, 'weight'=> options.delete('columnweight')) if options.keys.include?('columnweight')
          TkGrid.columnconfigure(griddable_parent_proxy.tk, index_in_parent, 'minsize'=> options.delete('columnminsize')) if options.keys.include?('columnminsize')
        end
        griddable_proxy&.tk&.grid(options)
      end
      
      def font=(value)
        if (value.is_a?(Symbol) || value.is_a?(String)) && FONTS_PREDEFINED.include?(value.to_s.downcase)
          @tk.font = "tk_#{value}_font".camelcase(:upper)
        else
          @tk.font = value.is_a?(TkFont) ? value : TkFont.new(value)
        end
      rescue => e
        Glimmer::Config.logger.debug {"Failed to set attribute #{attribute} with args #{args.inspect}. Attempting to set through style instead..."}
        Glimmer::Config.logger.debug {e.full_message}
        apply_style({"font" => value})
      end
      
      def destroy
        @tk.destroy
        @on_destroy_procs&.each {|p| p.call(@tk)}
      end
      
      def apply_style(options)
        @@style_number = 0 unless defined?(@@style_number)
        style = "style#{@@style_number += 1}.#{@tk.class.name.split('::').last}"
        ::Tk::Tile::Style.configure(style, options)
        @tk.style = style
      end
      
      def widget_custom_attribute_mapping
        # TODO consider extracting to modules/subclasses
        @widget_custom_attribute_mapping ||= {
          ::Tk::Tile::TButton => {
            'image' => {
              getter: {name: 'image', invoker: lambda { |widget, args| @tk.image }},
              setter: {name: 'image=', invoker: lambda { |widget, args| @tk.image = image_argument(args) }},
            },
          },
          ::Tk::Tile::TCheckbutton => {
            'image' => {
              getter: {name: 'image', invoker: lambda { |widget, args| @tk.image }},
              setter: {name: 'image=', invoker: lambda { |widget, args| @tk.image = image_argument(args) }},
            },
            'variable' => {
              getter: {name: 'variable', invoker: lambda { |widget, args| @tk.variable&.value.to_s == @tk.onvalue.to_s }},
              setter: {name: 'variable=', invoker: lambda { |widget, args| @tk.variable&.value = args.first.is_a?(Integer) ? args.first : (args.first ? 1 : 0) }},
            },
          },
          ::Tk::Tile::TRadiobutton => {
            'image' => {
              getter: {name: 'image', invoker: lambda { |widget, args| @tk.image }},
              setter: {name: 'image=', invoker: lambda { |widget, args| @tk.image = image_argument(args) }},
            },
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.text }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.value = @tk.text = args.first }},
            },
            'variable' => {
              getter: {name: 'variable', invoker: lambda { |widget, args| @tk.variable&.value == @tk.value }},
              setter: {name: 'variable=', invoker: lambda { |widget, args| @tk.variable&.value = args.first ? @tk.value : @tk.variable&.value }},
            },
          },
          ::Tk::Tile::TCombobox => {
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.textvariable&.value }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.textvariable&.value = args.first }},
            },
          },
          ::Tk::Tile::TLabel => {
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.textvariable&.value }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.textvariable&.value = args.first }},
            },
            'image' => {
              getter: {name: 'image', invoker: lambda { |widget, args| @tk.image }},
              setter: {name: 'image=', invoker: lambda { |widget, args| @tk.image = image_argument(args) }},
            },
          },
          ::Tk::Tile::TEntry => {
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.textvariable&.value }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.textvariable&.value = args.first }},
            },
          },
          ::Tk::Tile::TSpinbox => {
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.textvariable&.value }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.textvariable&.value = args.first }},
            },
          },
          ::Tk::Root => {
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.title }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.title = args.first }},
            },
          },
        }
      end
      
      def widget_attribute_listener_installers
        # TODO consider extracting to modules/subclasses
        @tk_widget_attribute_listener_installers ||= {
          ::Tk::Tile::TCheckbutton => {
            'variable' => lambda do |observer|
              @tk.command {
                observer.call(@tk.variable.value.to_s == @tk.onvalue.to_s)
              }
            end,
          },
          ::Tk::Tile::TCombobox => {
            'text' => lambda do |observer|
              if observer.is_a?(Glimmer::DataBinding::ModelBinding)
                model = observer.model
                options_model_property = observer.property_name + '_options'
                # TODO perform data-binding to values too
                @tk.values = model.send(options_model_property) if model.respond_to?(options_model_property)
              end
              @tk.bind('<ComboboxSelected>') {
                observer.call(@tk.textvariable.value)
              }
            end,
          },
          ::Tk::Tile::TEntry => {
            'text' => lambda do |observer|
              @tk.textvariable.trace('write') {
                observer.call(@tk.textvariable.value)
              }
            end,
          },
          ::Tk::Tile::TSpinbox => {
            'text' => lambda do |observer|
              @tk.command {
                observer.call(@tk.textvariable&.value)
              }
              @tk.validate('key')
              @tk.validatecommand { |validate_args|
                observer.call(validate_args.value)
                new_icursor = validate_args.index
                new_icursor += validate_args.string.size if validate_args.action == 1
                @tk.icursor = new_icursor
                true
              }
            end,
          },
          ::Tk::Text => {
            'value' => lambda do |observer|
              handle_listener('modified') do
                observer.call(value)
              end
            end,
          },
          ::Tk::Tile::TRadiobutton => {
            'variable' => lambda do |observer|
              @tk.command {
                observer.call(@tk.variable.value == @tk.value)
              }
            end,
          },
        }
      end
      
      def image_argument(args)
        if args.first.is_a?(::TkPhotoImage)
          args.first
        else
          image_args = {}
          image_args.merge!(file: args.first.to_s) if args.first.is_a?(String)
          the_image = ::TkPhotoImage.new(image_args)
          if args.last.is_a?(Hash)
            processed_image = ::TkPhotoImage.new
            processed_image.copy(the_image, args.last)
            the_image = processed_image
          end
          the_image
        end
      end
      
      def add_observer(observer, attribute)
        attribute_listener_installers = @tk.class.ancestors.map {|ancestor| widget_attribute_listener_installers[ancestor]}.compact
        widget_listener_installers = attribute_listener_installers.map{|installer| installer[attribute.to_s]}.compact if !attribute_listener_installers.empty?
        widget_listener_installers.to_a.first&.call(observer)
      end
      
      def handle_listener(listener_name, &listener)
        listener_name = listener_name.to_s
        # TODO return a listener registration object that has a deregister method
        if listener_name == 'destroy'
          # 'destroy' is a more reliable alternative listener binding to '<Destroy>'
          @on_destroy_procs ||= []
          listener.singleton_class.include(Glimmer::DataBinding::Tk::OneTimeObserver) unless listener.is_a?(Glimmer::DataBinding::Tk::OneTimeObserver)
          @on_destroy_procs << listener
          @tk.bind('<Destroy>', listener)
          parent_proxy.handle_listener(listener_name, &listener) if parent_proxy
        else
          @listeners ||= {}
          begin
            @listeners[listener_name] ||= []
            if @tk.respond_to?(listener_name)
              @tk.send(listener_name) { |*args| @listeners[listener_name].each {|l| l.call(*args)} } if @listeners[listener_name].empty?
            else
              @tk.bind(listener_name) { |*args| @listeners[listener_name].each {|l| l.call(*args)} } if @listeners[listener_name].empty?
            end
            @listeners[listener_name] << listener
          rescue => e
            @listeners.delete(listener_name)
            Glimmer::Config.logger.debug {"Unable to bind to #{listener_name} .. attempting to surround with <> ..."}
            Glimmer::Config.logger.debug {e.full_message}
            new_listener_name = listener_name
            new_listener_name = "<#{new_listener_name}" if !new_listener_name.start_with?('<')
            new_listener_name = "#{new_listener_name}>" if !new_listener_name.end_with?('>')
            @listeners[new_listener_name] ||= []
            @tk.bind(new_listener_name) { |*args| @listeners[new_listener_name].each {|l| l.call(*args)} } if @listeners[new_listener_name].empty?
            @listeners[new_listener_name] << listener
          end
        end
      end
      
      def on(listener_name, &listener)
        handle_listener(listener_name, &listener)
      end
      
      def content(&block)
        Glimmer::DSL::Engine.add_content(self, Glimmer::DSL::Tk::WidgetExpression.new, keyword, *args, &block)
      end

      def method_missing(method, *args, &block)
        method = method.to_s
        if args.empty? && block.nil? && ((widget_custom_attribute_mapping[tk.class] && widget_custom_attribute_mapping[tk.class][method]) || has_state?(method) || has_attributes_attribute?(method))
          get_attribute(method)
        elsif method.end_with?('=') && block.nil? && ((widget_custom_attribute_mapping[tk.class] && widget_custom_attribute_mapping[tk.class][method.sub(/=$/, '')]) || has_state?(method) || has_attributes_attribute?(method))
          set_attribute(method.sub(/=$/, ''), *args)
        else
          tk.send(method, *args, &block)
        end
      rescue => e
        Glimmer::Config.logger.debug {"Neither WidgetProxy nor #{tk.class.name} can handle the method ##{method}"}
        super(method.to_sym, *args, &block)
      end
      
      def respond_to?(method, *args, super_only: false, &block)
        super(method, true) ||
          !super_only && tk.respond_to?(method, *args, &block)
      end
      
      private
      
      # The griddable parent widget proxy to apply grid to (is different from @tk in composite widgets like notebook or scrolledframe)
      def griddable_parent_proxy
        @parent_proxy
      end
      
      # The griddable widget proxy to apply grid to (is different from @tk in composite widgets like notebook or scrolledframe)
      def griddable_proxy
        self
      end
      
      def build_widget
        tk_widget_class = self.class.tk_widget_class_for(@keyword)
        @tk = tk_widget_class.new(@parent_proxy.tk, *args)
      end
      
      def initialize_defaults
        options = {}
        options[:sticky] = 'nsew'
        options[:column_weight] = 1 if @parent_proxy.children.count == 1
        grid(options) unless @tk.is_a?(::Tk::Toplevel) || @tk.is_a?(::Tk::Menu) || @tk.nil? # TODO refactor by adding a griddable? method that could be overriden by subclasses to consult for this call
      end
    end
  end
end

Dir[File.expand_path('./*_proxy.rb', __dir__)].each {|f| require f}
