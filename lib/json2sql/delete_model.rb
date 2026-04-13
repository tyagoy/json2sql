module Json2sql

  # Builds a DELETE FROM statement for a single table.
  #
  # Input Hash:
  #   "and" => { ... }   – WHERE conditions (required to avoid deleting all rows)
  #   "or"  => { ... }   – WHERE conditions (OR)

  class DeleteModel

    def initialize(sql, table, relation)

      @sql = sql

      @table = table.to_s

      @relation = relation
    end

    def build(params)

      @sql << "DELETE FROM "

      @sql << Sanitizer.keyword_wrap(@table)

      WhereModel.new(@sql, @table, @relation).build(params)
    end
    
  end

end
