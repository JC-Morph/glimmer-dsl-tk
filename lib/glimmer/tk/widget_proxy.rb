# Copyright (c) 2020-2022 Andy Maleh
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

require 'yaml'
require 'glimmer/data_binding/tk/one_time_observer'
require 'glimmer/tk/widget'
require 'glimmer/tk/draggable_and_droppable'

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
      
      prepend DraggableAndDroppable
      
      FONTS_PREDEFINED = %w[default text fixed menu heading caption small_caption icon tooltip]
      HEXADECIMAL_CHARACTERS = %w[0 1 2 3 4 5 6 7 8 9 a b c d e f]
      
      attr_reader :parent_proxy, :tk, :args, :keyword, :children, :bind_ids, :destroyed
      alias destroyed? destroyed

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
      alias closest_window toplevel_parent_proxy
      
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
        attribute = attribute.to_s
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
        attribute = attribute.to_s
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
          args = normalize_attribute_arguments(attribute, args)
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
      
      def style=(style_or_styles)
        if style_or_styles.is_a? String
          @tk.style(style_or_styles)
        else
          style_or_styles.each do |attribute, value|
            apply_style(attribute => value)
          end
        end
      end

      def grid(options = {})
        @_visible = true
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
        options['columnminsize'] = options['rowminsize'] = options.delete('minsize') if options.keys.include?('minsize')
        options['rowuniform'] = options.delete('row_uniform') || options.delete('rowuniform')
        options['columnuniform'] = options.delete('column_uniform') || options.delete('columnuniform')
        index_in_parent = griddable_parent_proxy&.children&.index(griddable_proxy)
        if index_in_parent
          TkGrid.rowconfigure(griddable_parent_proxy.tk, index_in_parent, 'weight'=> options.delete('rowweight')) if options.keys.include?('rowweight')
          TkGrid.rowconfigure(griddable_parent_proxy.tk, index_in_parent, 'minsize'=> options.delete('rowminsize')) if options.keys.include?('rowminsize')
          TkGrid.rowconfigure(griddable_parent_proxy.tk, index_in_parent, 'uniform'=> options.delete('rowuniform')) if options.keys.include?('rowuniform')
          TkGrid.columnconfigure(griddable_parent_proxy.tk, index_in_parent, 'weight'=> options.delete('columnweight')) if options.keys.include?('columnweight')
          TkGrid.columnconfigure(griddable_parent_proxy.tk, index_in_parent, 'minsize'=> options.delete('columnminsize')) if options.keys.include?('columnminsize')
          TkGrid.columnconfigure(griddable_parent_proxy.tk, index_in_parent, 'uniform'=> options.delete('columnuniform')) if options.keys.include?('columnuniform')
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
        children.each(&:destroy)
        unbind_all
        @tk.destroy
        @on_destroy_procs&.each {|p| p.call(@tk)}
        @destroyed = true
      end
      
      def apply_style(options)
        @@style_number = 0 unless defined?(@@style_number)
        style = "style#{@@style_number += 1}.#{@tk.class.name.split('::').last}"
        ::Tk::Tile::Style.configure(style, options)
        @tk.style = style
      end
      
      def normalize_attribute_arguments(attribute, args)
        attribute_argument_normalizers[attribute]&.call(args) || args
      end
      
      def attribute_argument_normalizers
        color_normalizer = lambda do |args|
          if args.size > 1 || args.first.is_a?(Numeric)
            rgb = args
            rgb = rgb.map(&:to_s).map(&:to_i)
            rgb = 3.times.map { |n| rgb[n] || 0}
            hex = rgb.map { |color| color.to_s(16).ljust(2, '0') }.join
            ["##{hex}"]
          elsif args.size == 1 &&
                args.first.is_a?(String) &&
                !args.first.start_with?('#') &&
                (args.first.size == 3 || args.first.size == 6)  &&
                (args.first.chars.all? {|char| HEXADECIMAL_CHARACTERS.include?(char.downcase)})
            ["##{args.first}"]
          else
            args
          end
        end
        @attribute_argument_normalizers ||= {
          'background' => color_normalizer,
          'foreground' => color_normalizer,
        }
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
          ::Tk::Tile::TScale => {
            'variable' => {
              getter: {name: 'variable', invoker: lambda { |widget, args| @tk.variable&.value }},
              setter: {name: 'variable=', invoker: lambda { |widget, args| @tk.variable&.value = args.first }},
            },
          },
          ::Tk::Root => {
            'text' => {
              getter: {name: 'text', invoker: lambda { |widget, args| @tk.title }},
              setter: {name: 'text=', invoker: lambda { |widget, args| @tk.title = args.first }},
            },
            'icon_photo' => {
              getter: {name: 'icon_photo', invoker: lambda { |widget, args| @tk.iconphoto }},
              setter: {name: 'icon_photo=', invoker: lambda { |widget, args| @tk.iconphoto = image_argument(args) }},
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
                if model.respond_to?(options_model_property)
                  options_observer = Glimmer::DataBinding::Observer.proc do
                    @tk.values = model.send(options_model_property)
                  end
                  options_observer.observe(model, options_model_property)
                  options_observer.call
                end
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
          ::Tk::Tile::TScale => {
            'variable' => lambda do |observer|
              @tk.command {
                observer.call(@tk.variable&.value)
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

      def event_generate(event_name, data = nil)
        data = YAML.dump(data) if data && !data.is_a?(String)
        tk.event_generate("<#{event_name}>", data: data)
      end

      def unbind_all
        @listeners&.keys&.each do |key|
          if key.to_s.downcase.include?('command')
            @tk.send(key, '')
          else
            @tk.bind_remove(key)
          end
        end
        @listeners = nil
      end

      def clear_children
        children.each(&:destroy)
        @children = []
      end

      def content(&block)
        Glimmer::DSL::Engine.add_content(self, Glimmer::DSL::Tk::WidgetExpression.new, keyword, *args, &block)
      end

      def window?
        false
      end

      def visible
        @visible = true if @visible.nil?
        @visible
      end
      alias visible? visible

      def visible=(value)
        value = !!value
        return if visible == value

        if value
          grid
        else
          tk.grid_remove
        end
        @visible = value
      end

      def hidden
        !visible
      end
      alias hidden? hidden

      def hidden=(value)
        self.visible = !value
      end

      def enabled
        tk.state == 'normal'
      end
      alias enabled? enabled

      def enabled=(value)
        tk.state = !!value ? 'normal' : 'disabled'
      end

      def disabled
        !enabled
      end
      alias disabled? disabled

      def disabled=(value)
        self.enabled = !value
      end

      def method_missing(method, *args, &block)
        method = method.to_s
        attribute_name = method.sub(/=$/, '')
        args = normalize_attribute_arguments(attribute_name, args)
        if args.empty? && block.nil? && ((widget_custom_attribute_mapping[tk.class] && widget_custom_attribute_mapping[tk.class][method]) || has_state?(method) || has_attributes_attribute?(method))
          get_attribute(method)
        elsif method.end_with?('=') && block.nil? && ((widget_custom_attribute_mapping[tk.class] && widget_custom_attribute_mapping[tk.class][method.sub(/=$/, '')]) || has_state?(method) || has_attributes_attribute?(method))
          set_attribute(attribute_name, *args)
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
      
      # inspect is overridden to prevent printing very long stack traces
      def inspect
        "#{super[0, 150]}... >"
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
        @tk = tk_widget_class.new(@parent_proxy.tk, *args).tap {|tk| tk.singleton_class.include(Glimmer::Tk::Widget); tk.proxy = self}
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
