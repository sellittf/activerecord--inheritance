module ActiveRecord
  module Inheritance
    class Base < ActiveRecord::Base

#    #####################
#    def type
#      self[:type]
#    end
#
#    def type=(value)
#      self[:type] = value
#    end
#    #####################


    # Overriding
    def create
      if self.id.nil? && connection.prefetch_primary_key?(self.class.table_name)
        self.id = connection.next_sequence_value(self.class.sequence_name)
      end

      # TODO crated_at, updated_at
      self.type = self.class.name

      self.class.all_classes.each do |klass|

        quoted_table_name = self.connection.quote_table_name(klass.write_table)
        #old#
        column_names = klass.write_columns.collect {|column| column.name unless read_attribute(column.name).nil? }.compact # or column.primary
        quoted_column_names = column_names.collect {|name| self.connection.quote_column_name(name) }
        attributes_values = column_names.collect {|name| read_attribute(name) }
        quoted_attributes_values = attributes_values.collect {|value| self.connection.quote(value) }

        statement = "INSERT INTO #{quoted_table_name} " +
                    "(#{quoted_column_names.join(', ')}) " +
                    "VALUES(#{quoted_attributes_values.join(', ')})"

        #new#
        #        quoted_set = klass.write_columns.collect { |column|
        #          "#{self.connection.quote_column_name(column.name)} = #{self.connection.quote(read_attribute(column.name))}" unless read_attribute(column.name).nil?
        #        }.compact
        #
        #        statement = "INSERT INTO #{quoted_table_name} " +
        #                    "SET #{quoted_set.join(', ')} "

        self.id = connection.insert(statement, "#{self.class.name} Create",
        self.class.primary_key, self.id, self.class.sequence_name)
      end

      @new_record = false
      id
    end

    # Overriding
    def update(attribute_names = nil) # TODO before (attribute_names = @attributes.keys)
      # TODO crated_at, updated_at
      return 0 if changes.empty?

      self.class.all_classes.each do |klass|
        quoted_table_name = self.connection.quote_table_name(klass.write_table)

        quoted_set = klass.write_columns.collect { |column|
          "#{self.connection.quote_column_name(column.name)} = #{self.connection.quote(read_attribute(column.name))}" if changed.include?(column.name)
          }.compact

          unless quoted_set.empty?
            statement = "UPDATE #{quoted_table_name} " +
                        "SET #{quoted_set.join(', ')} " +
                        "WHERE #{connection.quote_column_name(self.class.primary_key)} = #{quoted_id}"

            connection.update(statement, "#{self.class.name} Update")
          end
        end
      end


      # Overriding
      def destroy
        unless new_record?
          transaction do
            self.class.all_classes.each do |klass|
              quoted_table_name = self.connection.quote_table_name(klass.write_table)

              statement = "DELETE FROM #{quoted_table_name} " +
                          "WHERE #{connection.quote_column_name(self.class.primary_key)} = #{quoted_id}"

              connection.delete(statement, "#{self.class.name} Destroy")
            end
          end
        end

        freeze
      end

      # TODO
      # Overriding
      #  def delete_all(conditions = nil)
      #    sql = "DELETE FROM #{quoted_table_name} "
      #    add_conditions!(sql, conditions, scope(:find))
      #    connection.delete(sql, "#{name} Delete all")
      #  end


      # Overriding
      #  def attributes_from_column_definition
      #    a = self.class.columns.inject({}) do |attributes, column|
      #      attributes[column.name] = column.default unless column.name == self.class.primary_key
      #      attributes
      #    end
      #    unless self.class.all_classes.empty?
      #      a = self.class.all_classes.collect {|klass| klass[1][:columns] }.flatten.inject(a) do |attributes, column|
      #        attributes[column.name] = column.default unless column.name == self.class.primary_key
      #        attributes
      #      end
      #    end
      #    a
      #  end


      class << self

        def inherited(subclass)
          super
          subclass.reset_table_name
        end
   
        def view_table_required?
          superclass != ActiveRecord::Inheritance::Base
        end
   
        def write_table
          @write_table ||= undecorated_table_name(name)
        end

        def read_table
          @read_table ||= (view_table_required? ? "#{write_table}_view" : write_table)
        end

        def write_columns
          unless defined?(@write_columns) && @write_columns
            @write_columns = connection.columns(write_table, "#{name} Columns")
            @write_columns.each { |column| column.primary = column.name == primary_key }
          end
          @write_columns
        end

        def all_classes
          unless defined?(@all_classes) && @all_classes
            @all_classes = []
            klass = self
            until klass == ActiveRecord::Inheritance::Base do
              @all_classes << klass
              klass = klass.superclass
            end
            @all_classes.reverse!
          end
          @all_classes
        end

        def sql_create_view
          return unless view_table_required?
          super_columns = superclass.columns.collect {|column| "#{connection.quote_table_name(superclass.read_table)}.#{connection.quote_column_name(column.name)}" unless column.name == superclass.primary_key }.compact.join(', ')
          "CREATE OR REPLACE VIEW #{connection.quote_table_name(read_table)} AS
          SELECT #{connection.quote_table_name(write_table)}.*, #{super_columns}
          FROM #{connection.quote_table_name(write_table)} LEFT JOIN #{connection.quote_table_name(superclass.read_table)}
          USING (#{connection.quote_column_name(primary_key)});"
        end

        def sql_drop_view
          return unless view_table_required?
          "DROP VIEW IF EXISTS #{connection.quote_table_name(read_table)}"
        end

        # Overriding
        def base_class
          self
        end

        # Overriding
        def descends_from_active_record?
          true  
        end

        # Overriding
#        def set_table_name(value = nil, &block)
#          value = read_table
#          super
#        end
        
        # Overriding
        def reset_table_name
          name = read_table
# TODO    name = (connection.table_exists?(read_table) ? read_table : write_table)
          set_table_name(name)
          name
        end

        # Overriding
        def find(*args)
#old#     reset_table_name unless table_name == read_table  # make sure the read_table is set

          # TODO DONE select by type is redundant (used by STI)
          a = super
          
          # TODO merge subclasses by type and reload with "WHERE id IN (...)"
          Array(a).each {|b| b.reload unless b.class == self }
          a
        end

      end

    end
  end
end