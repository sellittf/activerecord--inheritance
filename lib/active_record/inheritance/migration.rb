module ActiveRecord
  module Inheritance
    class Migration < ActiveRecord::Migration

      class << self

        def method_missing(method, *arguments, &block)
          result = super

          if method == :create_table or method == :drop_table
            begin
              klass = arguments.first.to_s.classify.constantize
              case method
                when :create_table
                  if klass.view_table_required?
                    execute(klass.sql_create_view)
                  else
                    add_column(arguments.first, :type, :string)
                  end
                when :drop_table
                  execute(klass.sql_drop_view) if klass.view_table_required?
              end
            rescue
              # nothing
            end
          end

          return result
        end
      
      end
    end

  end
end
