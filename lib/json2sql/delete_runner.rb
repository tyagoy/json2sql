module Json2sql

  # Builds one or more DELETE statements from a Hash of table → params.
  #
  # Usage (single deletion):
  #   sql = Json2sql::DeleteRunner.build(
  #     "users" => { "and" => { "id" => 42 } }
  #   )
  #
  # Usage (multiple deletions — value is an Array):
  #   sql = Json2sql::DeleteRunner.build(
  #     "sessions" => [
  #       { "and" => { "user_id" => 1 } },
  #       { "and" => { "user_id" => 2 } }
  #     ]
  #   )

  class DeleteRunner

    def self.build(input)

      sql = +""
      
      input = Json2sql.normalize(input)

      relation = WhereRelation.none("")

      input.each do |table, value|

        tbl = table.to_s

        case value

        when Hash

          DeleteModel.new(sql, tbl, relation).build(value)

          sql << ";\n"

        when Array

          value.each do |item|

            next unless item.is_a?(Hash)

            DeleteModel.new(sql, tbl, relation).build(item)
            
            sql << ";\n"
          end
        end
      end

      sql
    end
    
  end

end
