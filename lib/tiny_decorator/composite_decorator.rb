module TinyDecorator
  #
  # Passing only decorator name, object will be decorated
  # 
  # ```
  #   extend TinyDecorator::CompositeDecorator
  #   decorated_by :default, 'DefaultDecorator'
  # ```
  #
  # Passing only 1 block param to #decorated_by
  # Execute block to get decorator name.
  # ```
  #   extend TinyDecorator::CompositeDecorator
  #   decorated_by :default, ->(record) { record.nil? ? 'NilDecorator' : 'DefaultDecorator' }
  #   decorated_by :default, ->(record, context) { record.in(context).nil? ? 'NilDecorator' : 'DefaultDecorator' }
  # ```
  #
  # Passing decorator name and 1 block param to #decorated_by
  # Execute block to determine should we decorate it or not
  # ```
  #   extend TinyDecorator::CompositeDecorator
  #   decorated_by :default, ->(record) { record.valid? ? 'ValidDecorator' : 'InvalidDecorator' }
  #   decorated_by :default, ->(record, context) { record.in(context).valid? ? 'ValidDecorator' : 'InvalidDecorator' }
  # ```
  #
  # For now, `:name` is redundant, but it's nice to have a friendly name for readbility and later usage
  #
  # Block may receive
  #   1 parameter is record to decorate OR
  #   2 parameters are record to decorate and context
  #
  # CompositeDecorator introduces a central conditional decorator manager.
  # It answer the questions: which decorater will be used in which conditions.
  # The decorator is a sub class of TinyDecorator::BaseDelegator (or draper decorator, but not recommend)
  # TinyDecorator::BaseDelegator will answer the question which attributes are decorated.
  #
  # In case we don't have eager loading or rails' eager loading doesn't match,
  #   preload block could be used to manually load data to avoid N+1.
  #   Then access through 3rd param of decorator
  #
  # ```ruby
  #   preload :count_all, ->(all_records, context, preloaded) { Group(all_records).count }
  # ```
  #   all_records - all the records to decorate
  #   context     - The context passed to collection decorating,
  #     because preload run once before all decratings, this is the only cotext we have at this time
  #   preloaded   - all preloaded before. For perfomrance, it's mutable, please handle with care
  #
  module CompositeDecorator
    # Decorate collection of objects, each object is decorate by `#decorate`
    # TODO: [AV] It's greate if with activerecord relationship, we defer decorate until data retrieved.
    #       Using `map` will make data retrieval executes immediately
    def decorate_collection(records, context = {})
      if instance_variable_get(:@_preloaders)
        preloaded = {}
        instance_variable_get(:@_preloaders).each do |preloader, execute_block|
          preloaded[preloader] = execute_block.call(records, context, preloaded)
        end
      end

      Array(records).map do |record|
        decorate(record, context, preloaded)
      end
    end

    # Decorate an object by defined `#decorated_by`
    def decorate(record, context = {}, preloaded = {})
      if instance_variable_get(:@_contexts)
        context = context.merge(instance_variable_get(:@_contexts).inject({}) do |carry, (context_name, context_block)|
          context[context_name] = context_block.call(record, context)

          carry
        end)
      end

      instance_variable_get(:@_decorators).inject(record) do |carry, (name, value)|
        decorator = decorator_resolver(name, value, record, context)
        if decorator
          carry = begin
            const_get(decorator, false)
          rescue NameError
            Object.const_get(decorator, false)
          end.decorate(carry, context, preloaded)
        end

        carry
      end
    end

    private

    # decorated_by
    def decorated_by(decorate_name, class_name, condition_block = nil)
      decorators = instance_variable_get(:@_decorators) || {}
      decorators[decorate_name] = [class_name, condition_block]
      instance_variable_set(:@_decorators, decorators)
    end

    # set_context
    def set_context(context_name, context_block)
      _contexts = instance_variable_get(:@_contexts) || {}
      _contexts[context_name] = context_block
      instance_variable_set(:@_contexts, _contexts)
    end

    # preload
    # Similar to context. but run once on whole collection
    # preload preload_name, ->(records, preloaded) do
    #   Relation.where(id: records.map(&:relation_id).compact.uniq)
    # end
    def preload(preloader, preloader_block)
      _preloaders = instance_variable_get(:@_preloaders) || {}
      _preloaders[preloader] = preloader_block
      instance_variable_set(:@_preloaders, _preloaders)
    end

    # Resolve decorator class from #decorated_by definition
    # if 1st param is a block, evaluate it as decorator name
    # if 1st param isn't a block
    #     if no 2nd param, 1st param is decorator name
    #     if 2nd param exists, evaluate it as boolean to determine decorate or not
    def decorator_resolver(_name, value, record, context)
      if value[0].respond_to?(:call)
        ((value[0].arity == 1 && value[0].call(record)) || (value[0].arity == 2 && value[0].call(record, context)))
      elsif value[1].nil? || (value[1].arity == 1 && value[1].call(record)) || (value[1].arity == 2 && value[1].call(record, context))
        value[0]
      end
    end
  end
end
