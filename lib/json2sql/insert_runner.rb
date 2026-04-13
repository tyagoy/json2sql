module Json2sql
  # Builds one or more INSERT statements from a Hash of table → params.
  #
  # Usage (single row):
  #   sql = Json2sql::InsertRunner.build(
  #     "users" => { "columns" => { "name" => "João", "email" => "j@x.com" } }
  #   )
  #
  # Usage (multiple rows — value is an Array):
  #   sql = Json2sql::InsertRunner.build(
  #     "tags" => [
  #       { "columns" => { "name" => "ruby" } },
  #       { "columns" => { "name" => "rails" } }
  #     ]
  #   )
  class InsertRunner

    def self.build(input)

      sql = +""

      input = Json2sql.normalize(input)

      input.each do |table, value|
        
        tbl = table.to_s

        case value
        when Hash
          InsertModel.new(sql, tbl).build(value)
          sql << ";\n"
        when Array
          value.each do |item|
            next unless item.is_a?(Hash)

            InsertModel.new(sql, tbl).build(item)
            sql << ";\n"
          end
        end
      end

      sql
    end
  end
end
