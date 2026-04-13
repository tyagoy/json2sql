module Json2sql
  # Builds an INSERT INTO statement for a single table.
  #
  # Input Hash:
  #   "columns" => { "col_name" => value, ... }
  #
  # Values:
  #   Integer / Float → inserted as raw numbers
  #   String          → wrapped in single quotes with SQL escaping
  class InsertModel
    def initialize(sql, table)
      @sql   = sql
      @table = table.to_s
    end

    def build(params)
      @sql << "INSERT INTO "
      @sql << Sanitizer.keyword_wrap(@table)
      @sql << " ("
      build_columns(params)
      @sql << ") VALUES ("
      build_values(params)
      @sql << ")"
    end

    private

    def build_columns(params)
      columns  = params["columns"]
      return unless columns.is_a?(Hash)

      separator = false
      columns.each_key do |key|
        @sql << ", " if separator
        separator = true
        @sql << Sanitizer.keyword_wrap(key.to_s)
      end
    end

    def build_values(params)
      columns  = params["columns"]
      return unless columns.is_a?(Hash)

      separator = false
      columns.each_value do |value|
        @sql << ", " if separator
        separator = true

        case value
        when Integer, Float then @sql << value.to_s
        when String         then @sql << Sanitizer.value_wrap(value)
        end
      end
    end
  end
end
