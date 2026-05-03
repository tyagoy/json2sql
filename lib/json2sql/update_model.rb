module Json2sql

  # Builds an UPDATE statement for a single table.
  #
  # Input Hash:
  #   "columns" => { "col" => value, ... }  – columns to SET
  #   "and"     => { ... }                  – WHERE conditions
  #   "or"      => { ... }                  – WHERE conditions (OR)
  #
  # Value types follow the same rules as InsertModel.
  #
  # Auto-injected when absent: updated_at → NOW()

  class UpdateModel

    def initialize(sql, table, relation)

      @sql = sql

      @table = table.to_s

      @relation = relation
    end

    def build(params)

      columns = params["columns"]

      return unless columns.is_a?(Hash)

      columns = build_timestamp(columns)

      @sql << "UPDATE "

      @sql << Sanitizer.keyword_wrap(@table)

      @sql << " SET "

      build_columns(columns)

      WhereModel.new(@sql, @table, @relation).build(params)
    end

    private

    def build_timestamp(columns)

      return columns if columns.key?("updated_at")

      columns.merge("updated_at" => :now)
    end

    def build_columns(columns)

      separator = false

      columns.each do |key, value|

        @sql << ", " if separator

        separator = true

        column = key.to_s

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " = "

        case value
        when Float   then @sql << value.to_s
        when Integer then @sql << value.to_s
        when String  then @sql << Sanitizer.value_wrap(value)
        when :now    then @sql << "NOW()"
        end
      end
    end

  end
  
end
