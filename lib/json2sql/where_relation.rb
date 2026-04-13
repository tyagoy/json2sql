module Json2sql
  class WhereRelation
    NONE   = :none
    CHILD  = :child
    PARENT = :parent

    attr_reader :table, :kind

    def initialize(table, kind)
      @table = table.to_s
      @kind  = kind
    end

    # Factory: no relationship (top-level query).
    def self.none(table)
      new(table, NONE)
    end

    # Factory: foreign key is on the child table pointing to the parent.
    # Produces: `parent`.`child_id` = `current`.`id`
    def self.child(table)
      new(table, CHILD)
    end

    # Factory: foreign key is on the current/parent table pointing to the child.
    # Produces: `current`.`parent_id` = `parent`.`id`
    def self.parent(table)
      new(table, PARENT)
    end

    # Appends the JOIN condition for this relationship into sql.
    # +current+ is the name of the table being queried.
    def build_table_relation(sql, current)
      current = current.to_s

      if kind == CHILD
        sql << Sanitizer.keyword_wrap(table)
        sql << "."
        sql << build_table_id(current)
        sql << " = "
        sql << Sanitizer.keyword_wrap(current)
        sql << ".`id`"
        return
      end

      if kind == PARENT
        sql << Sanitizer.keyword_wrap(current)
        sql << "."
        sql << build_table_id(table)
        sql << " = "
        sql << Sanitizer.keyword_wrap(table)
        sql << ".`id`"
      end
    end

    # Converts a (possibly plural) table name to its foreign-key column
    # name wrapped in backticks.
    #   "users"      → "`user_id`"
    #   "categories" → "`category_id`"
    #   "admins"     → "`admin_id`"
    def build_table_id(tbl)
      tbl  = tbl.to_s
      base = Sanitizer.keyword(tbl)

      name = if base.end_with?("ies")
               base[0..-4] + "y"
             elsif base.end_with?("s")
               base[0..-2]
             else
               base
             end

      "`#{name}_id`"
    end
  end
end
