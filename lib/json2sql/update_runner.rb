module Json2sql

  # Builds one or more UPDATE statements from a Hash of table → params.
  #
  # Usage (single row):
  #   sql = Json2sql::UpdateRunner.build(
  #     "users" => {
  #       "columns" => { "name" => "Maria", "updated_at" => "2026-04-12" },
  #       "and"     => { "id" => 42 }
  #     }
  #   )
  #
  # Usage (multiple rows — value is an Array):
  #   sql = Json2sql::UpdateRunner.build(
  #     "settings" => [
  #       { "columns" => { "value" => "dark" },  "and" => { "key" => "theme" } },
  #       { "columns" => { "value" => "en" },    "and" => { "key" => "lang" } }
  #     ]
  #   )

  class UpdateRunner

    def self.build(input)

      sql = +""

      input = Json2sql.normalize(input)

      relation = WhereRelation.none("")

      input.each do |table, value|

        tbl = table.to_s

        case value
        
        when Hash

          UpdateModel.new(sql, tbl, relation).build(value)

          sql << ";\n"

        when Array

          value.each do |item|

            next unless item.is_a?(Hash)

            UpdateModel.new(sql, tbl, relation).build(item)

            sql << ";\n"
          end
        end
      end

      sql
    end
  end
end
