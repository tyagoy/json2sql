module Json2sql

  # Builds a SQL WHERE clause from a Hash describing the conditions.
  #
  # Input structure mirrors the JSON format used in the C++ backend:
  #
  #   {
  #     "and" => {
  #       "name"   => "john",           # implicit LIKE '%john%'
  #       "age"    => 30,               # implicit equality
  #       "status" => { "in" => [1,2] },
  #       "score"  => { ">=" => 4.5 },
  #       "col"    => { "null" => true },  # IS NULL / IS NOT NULL
  #       "ref"    => { "=" => "$.table.col" }  # column reference
  #     },
  #     "or" => { ... }
  #   }
  #
  # Supported operators: =  <  >  <=  >=  !=  <>
  #                       in  !in  like  !like
  # String pseudo-actions: contains (LIKE %v%), first (LIKE v%), last (LIKE %v)

  class WhereModel

    def initialize(sql, table, relation)

      @sql = sql

      @table = table.to_s

      @relation = relation
    end

    def build(params)

      has_relation  = @relation.kind != WhereRelation::NONE

      has_where_and = params["and"].is_a?(Hash)

      has_where_or  = params["or"].is_a?(Hash)

      return unless has_relation || has_where_and || has_where_or

      rules = []

      rules << with_buffer { @relation.build_table_relation(@sql, @table) } if has_relation

      scope = has_where_and ? " AND " : " OR "
      
      group = params["and"] || params["or"]

      if group

        rule = build_column_group(group, scope)

        rules << rule unless rule.empty?
      end

      return if rules.empty?

      @sql << " WHERE " << rules.join(" AND ")
    end

    private

    # -------------------------------------------------------------------------
    # Group level
    # -------------------------------------------------------------------------

    def build_column_group(params, scope)

      rules = params.filter_map do |key, value|

        rule = with_buffer { build_column_types(value, scope, key.to_s) }

        rule.empty? ? nil : rule
      end

      return "" if rules.empty?

      "(#{rules.join(scope)})"
    end

    # Dispatch by Ruby type of the value.
    
    def build_column_types(params, scope, column)

      case params

      when TrueClass, FalseClass

        build_action_types(params, column, "=")

      when Integer

        build_action_types(params, column, "=")

      when String

        build_action_types(params, column, "contains")

      when Hash

        if column == "and"

          rule = build_column_group(params, " AND ")

          @sql << rule unless rule.empty?

          return
        end

        if column == "or"

          rule = build_column_group(params, " OR ")

          @sql << rule unless rule.empty?

          return
        end

        build_action_group(params, scope, column)
      end
    end

    # -------------------------------------------------------------------------
    # Action level
    # -------------------------------------------------------------------------

    def build_action_group(params, scope, column)

      rules = params.filter_map do |key, value|

        rule = with_buffer { build_action_types(value, column, key.to_s) }

        rule.empty? ? nil : rule
      end

      @sql << rules.join(scope) unless rules.empty?
    end

    def build_action_types(params, column, action)

      if action == "and"

        build_column_types(params, " AND ", column)

        return
      end

      if action == "or"

        build_column_types(params, " OR ", column)

        return
      end

      build_action_values(params, column, action)
    end

    # -------------------------------------------------------------------------
    # Value level — emit the actual SQL comparison
    # -------------------------------------------------------------------------

    def build_action_values(params, column, action) # rubocop:disable Metrics/MethodLength

      case params
      
      when TrueClass, FalseClass

        # Only "null" → IS NULL / IS NOT NULL. Boolean equality is not emitted
        # (matches C++ behaviour — use integer 1/0 for boolean equality).
        return unless action == "null"

        action_str = params ? " IS " : " IS NOT "

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << action_str << "NULL"

      when Integer

        action_name = get_action(action)

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " #{action_name} #{params}"

      when Float

        action_name = get_action(action)

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " #{action_name} #{params}"

      when String

        build_action_string(params, column, action)

      when Array

        action_name = get_action(action)

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " #{action_name} ("

        build_array(params)

        @sql << ")"

      when Hash

        action_name = get_action(action)

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " #{action_name} ("

        build_object(params)

        @sql << ")"
      end
    end

    def build_action_string(params, column, action)

      action_name = get_action(action)

      case action_name

      when "last"

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " LIKE '%" << Sanitizer.value(params) << "'"

      when "first"

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " LIKE '" << Sanitizer.value(params) << "%'"

      when "contains"

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " LIKE '%" << Sanitizer.value(params) << "%'"

      else

        @sql << Sanitizer.keyword_wrap(@table) << "."

        @sql << Sanitizer.keyword_wrap(column)

        @sql << " #{action_name} "

        if params.start_with?("$.")

          @sql << Sanitizer.reference(params)

          return
        end

        @sql << Sanitizer.value_wrap(params)
      end
    end

    # -------------------------------------------------------------------------
    # IN-list and subquery helpers
    # -------------------------------------------------------------------------

    def build_array(array)

      if array.empty?

        @sql << "NULL"

        return
      end

      glue = false

      array.each do |item|

        @sql << ", " if glue

        glue = true

        case item
        when Float   then @sql << item.to_s
        when Integer then @sql << item.to_s
        when String  then @sql << Sanitizer.value_wrap(item)
        end
      end
    end

    # Builds a UNION of sub-SELECTs (used when action value is a Hash of tables).

    def build_object(object)

      if object.empty?

        @sql << "NULL"

        return
      end

      glue = false

      relation = WhereRelation.none(@table)

      object.each do |key, value|

        @sql << " UNION " if glue

        glue = true

        tbl = key.to_s

        @sql << "("

        SelectModel.new(@sql, tbl, relation).build_query_default(value)

        @sql << ")"
      end
    end

    # -------------------------------------------------------------------------
    # Buffer helper — temporarily swap @sql for a fresh string so that any
    # downstream << calls are captured in isolation. Returns the captured fragment.
    # -------------------------------------------------------------------------

    def with_buffer

      saved = @sql

      @sql = +""

      yield

      @sql

    ensure

      @sql = saved
    end

    # -------------------------------------------------------------------------
    # Operator mapping
    # -------------------------------------------------------------------------

    def get_action(action)

      case action
      when "in"    then "IN"
      when "!in"   then "NOT IN"
      when "like"  then "LIKE"
      when "!like" then "NOT LIKE"
      else action
      end
    end

  end
  
end
