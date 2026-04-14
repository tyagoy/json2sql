module Json2sql

  # Builds a SELECT SQL statement for a single table.
  #
  # Input Hash keys (all optional):
  #   "columns"  => ["id", "name", ...]   – columns to SELECT
  #   "where"    => { "and" => {...} }    – WHERE conditions (see WhereModel)
  #   "and"      => {...}                 – shorthand for top-level AND WHERE
  #   "or"       => {...}                 – shorthand for top-level OR WHERE
  #   "order"    => { "col" => "asc" }   – ORDER BY
  #   "limit"    => 10                   – LIMIT
  #   "offset"   => 20                   – OFFSET
  #   "options"  => ["total"]            – wrap response with data/total JSON
  #   "children" => { "table" => {...} } – nested child arrays
  #   "parents"  => { "table" => {...} } – nested parent objects

  class SelectModel

    def initialize(sql, table, relation)

      @sql = sql

      @table = table.to_s

      @relation = relation
    end

    # SELECT COUNT(*) AS `table` FROM `table` WHERE ...

    def build_query_count(params)

      @sql << "SELECT COUNT(*) AS "
      
      @sql << Sanitizer.keyword_wrap(@table)
      
      @sql << " FROM "
            
      @sql << Sanitizer.keyword_wrap(@table)

      WhereModel.new(@sql, @table, @relation).build(params)
    end

    # Plain SELECT col1, col2 FROM `table` WHERE ... ORDER BY ... LIMIT ... OFFSET ...

    def build_query_default(params)

      @sep = false

      @sql << "SELECT "

      build_columns_default(params)

      @sql << " FROM "

      @sql << Sanitizer.keyword_wrap(@table)

      WhereModel.new(@sql, @table, @relation).build(params)

      build_order(params)      
      build_limit(params)
      build_offset(params)
    end

    # SELECT JSON_ARRAYAGG(JSON_OBJECT(...)) AS `table`
    # FROM LATERAL (SELECT * FROM `table` WHERE ... ORDER ... LIMIT ...) AS `table`

    def build_query_array(params)

      @sep = false

      @sql << "SELECT JSON_ARRAYAGG(JSON_OBJECT("

      build_columns_json(params)
      build_columns_array(params)
      build_columns_object(params)

      @sql << ")) AS "

      @sql << Sanitizer.keyword_wrap(@table)

      @sql << " FROM LATERAL (SELECT * FROM "

      @sql << Sanitizer.keyword_wrap(@table)

      WhereModel.new(@sql, @table, @relation).build(params)

      build_order(params)
      build_limit(params)
      build_offset(params)

      @sql << ") AS "

      @sql << Sanitizer.keyword_wrap(@table)
    end

    # SELECT JSON_OBJECT(...) AS `table`
    # FROM LATERAL (SELECT * FROM `table` WHERE ...) AS `table`

    def build_query_object(params)

      @sep = false

      @sql << "SELECT JSON_OBJECT("

      build_columns_json(params)
      build_columns_array(params)
      build_columns_object(params)

      @sql << ") AS "

      @sql << Sanitizer.keyword_wrap(@table)

      @sql << " FROM LATERAL (SELECT * FROM "

      @sql << Sanitizer.keyword_wrap(@table)

      WhereModel.new(@sql, @table, @relation).build(params)

      build_order(params)
      build_limit(params)
      build_offset(params)

      @sql << ") AS "

      @sql << Sanitizer.keyword_wrap(@table)
    end

    # Smart dispatcher:
    #   - no options → build_query_array
    #   - options includes "total" → wraps with JSON_OBJECT('data', ..., 'total', COUNT(*))

    def build_query_options(params)

      options = params["options"]

      unless options.is_a?(Array) && !options.empty?

        build_query_array(params)

        return
      end

      total = options.include?("total")

      @sql << "SELECT JSON_OBJECT('data', ("

      build_query_array(params)

      @sql << ")"

      if total

        @sql << ", 'total', ("

        build_query_count(params)

        @sql << ")"
      end

      @sql << ")"
    end

    private

    # @sep is a shared separator flag used by build_columns_* to coordinate
    # comma placement across multiple calls within a single query build.

    # Appends plain column references: `table`.`col`, `table`.`col2`, ...

    def build_columns_default(params)

      columns = params["columns"]

      return unless columns.is_a?(Array)

      columns.each do |column|

        next unless column.is_a?(String) || column.is_a?(Symbol)

        @sql << ", " if @sep

        @sep = true

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column.to_s)
      end
    end

    # Appends JSON key-value pairs for columns: 'col', `table`.`col`, ...

    def build_columns_json(params)

      columns = params["columns"]

      return unless columns.is_a?(Array)

      columns.each do |column|

        next unless column.is_a?(String) || column.is_a?(Symbol)

        @sql << ", " if @sep

        @sep = true

        col = column.to_s

        @sql << Sanitizer.keyword_wrap(col, "'")

        @sql << ", "

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(col)
      end
    end

    # Appends nested child arrays (subquery → JSON_ARRAYAGG).
    # Uses WhereRelation::PARENT because child table references parent.
    
    def build_columns_array(params)

      children = params["children"]

      return unless children.is_a?(Hash)

      relation = WhereRelation.parent(@table)

      children.each do |key, value|

        next unless value.is_a?(Hash)

        @sql << ", " if @sep

        @sep = true

        tbl = key.to_s

        @sql << Sanitizer.keyword_wrap(tbl, "'")

        @sql << ", ("

        SelectModel.new(@sql, tbl, relation).build_query_options(value)

        @sql << ")"
      end
    end

    # Appends nested parent objects (subquery → JSON_OBJECT, single row).
    # Uses WhereRelation::CHILD because parent table is referenced from child.

    def build_columns_object(params)

      parents = params["parents"]

      return unless parents.is_a?(Hash)

      relation = WhereRelation.child(@table)

      parents.each do |key, value|

        next unless value.is_a?(Hash)

        @sql << ", " if @sep

        @sep = true

        tbl = key.to_s

        @sql << Sanitizer.keyword_wrap(tbl, "'")

        @sql << ", ("

        SelectModel.new(@sql, tbl, relation).build_query_object(value)

        @sql << ")"
      end
    end

    def build_order(params)

      order = params["order"]

      return unless order.is_a?(Hash) && !order.empty?

      @sql << " ORDER BY "

      glue = false

      order.each do |key, value|

        @sql << ", " if glue

        glue = true

        column = key.to_s

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        case value.to_s.downcase
        when "asc"  then @sql << " ASC"
        when "desc" then @sql << " DESC"
        end
      end
    end

    def build_limit(params)

      limit = params["limit"]

      @sql << " LIMIT #{limit}" if limit.is_a?(Integer)
    end

    def build_offset(params)

      offset = params["offset"]

      @sql << " OFFSET #{offset}" if offset.is_a?(Integer)
    end

  end
  
end
