module Json2sql
  # Builds a top-level SELECT statement from a Hash of table → params.
  #
  # Usage:
  #   sql = Json2sql::SelectRunner.build(
  #     "users" => {
  #       "columns" => ["id", "name", "email"],
  #       "and"     => { "active" => 1, "role" => { "in" => [1, 2] } },
  #       "order"   => { "created_at" => "desc" },
  #       "limit"   => 20,
  #       "offset"  => 0,
  #       "options" => ["total"]
  #     }
  #   )
  #
  # Output wraps every table in JSON_OBJECT so the client receives a single
  # JSON document:
  #   SELECT JSON_OBJECT('users', (...));
  class SelectRunner
    def self.build(input)
      input    = Json2sql.normalize(input)
      sql      = +""
      separator = false
      relation  = WhereRelation.none("")

      sql << "SELECT JSON_OBJECT("

      input.each do |table, value|
        next unless value.is_a?(Hash)

        sql << ", " if separator
        separator = true

        sql << Sanitizer.keyword_wrap(table.to_s, "'")
        sql << ", ("
        SelectModel.new(sql, table.to_s, relation).build_query_options(value)
        sql << ")"
      end

      sql << ");\n"
      sql
    end
  end
end
