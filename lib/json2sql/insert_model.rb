module Json2sql

  # Builds an INSERT INTO statement for a single table.
  #
  # Input Hash:
  #   "columns" => { "col_name" => value, ... }
  #
  # Values:
  #   Integer / Float → inserted as raw numbers
  #   String          → wrapped in single quotes with SQL escaping
  #
  # Auto-injected when absent: created_at and updated_at → NOW()

  class InsertModel

    def initialize(sql, table)

      @sql = sql

      @table = table.to_s
    end

    def build(params)

      columns = params["columns"]

      return unless columns.is_a?(Hash)

      columns = build_timestamps(columns)

      @sql << "INSERT INTO "

      @sql << Sanitizer.keyword_wrap(@table)

      @sql << " ("

      build_columns(columns)

      @sql << ") VALUES ("

      build_values(columns)

      @sql << ")"
    end

    private

    def build_timestamps(columns)

      timestamps = {}

      timestamps["created_at"] = :now unless columns.key?("created_at")

      timestamps["updated_at"] = :now unless columns.key?("updated_at")

      timestamps.empty? ? columns : columns.merge(timestamps)
    end

    def build_columns(columns)

      separator = false

      columns.each_key do |key|

        @sql << ", " if separator

        separator = true

        @sql << Sanitizer.keyword_wrap(key.to_s)
      end
    end

    def build_values(columns)

      separator = false

      columns.each_value do |value|

        @sql << ", " if separator

        separator = true

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
