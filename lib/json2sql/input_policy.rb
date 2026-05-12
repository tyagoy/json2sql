module Json2sql

  # Sanitizes a query input Hash before passing it to any Runner.
  #
  # Parameters:
  #   mode:   :allow (default) — only tables listed in `tables:` are accessible.
  #                              Tables absent from `tables:` are blocked entirely.
  #                              Empty `tables:` = no restriction.
  #           :deny            — all tables pass; only listed columns are stripped.
  #   tables: Per-table configuration Hash:
  #     { table_name => { columns: [...], where: { "and" => { col => val } } } }
  #     columns: column list — filtered by `mode` (allowed or denied).
  #              nil or absent = no column restriction for that table.
  #     where:   server-side conditions merged into "and". Forced keys overwrite
  #              user-supplied values — primary IDOR guard.
  #
  # Usage:
  #   policy = Json2sql::InputPolicy.new(
  #     mode:   :allow,
  #     tables: {
  #       orders: { columns: %w[id total status], where: { "and" => { "user_id" => 42 } } },
  #       users:  { columns: %w[id name email] }
  #     }
  #   )
  #   safe_input = policy.apply(raw_params)
  #   sql = Json2sql::SelectRunner.build(safe_input)

  class InputPolicy

    def initialize(mode: :allow, tables: {})

      @mode = mode

      @tables = Json2sql.normalize(tables)
    end

    # Returns a sanitized copy of input ready to pass to any Runner.
    # Runners remain unmodified — they receive only the clean Hash.

    def apply(input)

      input = Json2sql.normalize(input)

      input = filter_tables(input)

      input.each { |table, params| sanitize_table(params, table) }

      input
    end

    private

    def filter_tables(input)

      return input if @mode == :deny || @tables.empty?

      input.select { |table, _| @tables.key?(table) }
    end

    def sanitize_table(params, table)

      return unless params.is_a?(Hash)

      filter_columns(params, table)

      inject_where(params, table)

      %w[children parents].each do |relation|

        next unless params[relation].is_a?(Hash)

        params[relation].each { |child_table, child_params| sanitize_table(child_params, child_table) }
      end
    end

    # Filters "columns" using mode (:allow or :deny).
    # Handles Array (SELECT) and Hash (INSERT/UPDATE) column formats.
    # Hash entries (function columns) always pass through in :allow mode.
    # If no column list is defined for the table, columns are untouched.

    def filter_columns(params, table)

      columns = params["columns"]

      return unless columns.is_a?(Array) || columns.is_a?(Hash)

      list = @tables.dig(table, "columns")

      return unless list.is_a?(Array)

      params["columns"] = if @mode == :deny

        columns.is_a?(Array) \
          ? columns.reject { |c| list.include?(c) } \
          : columns.reject { |k, _| list.include?(k) }

      else

        columns.is_a?(Array) \
          ? columns.select { |c| c.is_a?(Hash) || list.include?(c) } \
          : columns.select { |k, _| list.include?(k) }

      end
    end

    # Merges forced "and" conditions into params["and"].
    # Forced keys overwrite user-supplied values for the same column,
    # preventing IDOR (e.g. attacker cannot override user_id).

    def inject_where(params, table)

      forced_and = @tables.dig(table, "where", "and")

      return unless forced_and.is_a?(Hash)

      params["and"] ||= {}

      params["and"].merge!(forced_and)
    end

  end
end
