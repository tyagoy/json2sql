module Json2sql

  # Sanitizes a query input Hash before passing it to any Runner.
  #
  # Parameters:
  #   mode:   :allow (default) — only tables listed in `tables:` are accessible.
  #                              Tables absent from `tables:` are blocked entirely.
  #                              Empty `tables:` = all tables blocked.
  #           :deny            — all tables pass. After column filtering, tables
  #                              with no remaining accessible columns are removed.
  #                              Same rule applies to children and parents.
  #   tables: Per-table configuration Hash (recursive):
  #     { table_name => { columns: [...],
  #                       children: { child_table => { columns: [...], ... } },
  #                       parents:  { parent_table => { columns: [...], ... } },
  #                       where: { "and" => { col => val } } } }
  #     columns:  column list — filtered by `mode` (allowed or denied).
  #               nil or absent = no column restriction for that table.
  #     children: nested hash of allowed/denied child tables with their own config.
  #               nil or absent = no restriction on children.
  #               In :deny mode: a child relation is removed only when all its
  #               columns are denied (result is empty array).
  #     parents:  nested hash of allowed/denied parent tables with their own config.
  #               nil or absent = no restriction on parents.
  #               In :deny mode: same rules as children.
  #     where:    server-side conditions merged into "and". Forced keys overwrite
  #               user-supplied values — primary IDOR guard.
  #
  # Usage:
  #   policy = Json2sql::QueryPolicy.new(
  #     mode:   :allow,
  #     tables: {
  #       orders: {
  #         columns:  %w[id total status],
  #         children: { order_items: { columns: %w[id price] } },
  #         parents:  { users: { columns: %w[id name] } },
  #         where:    { "and" => { "user_id" => 42 } }
  #       }
  #     }
  #   )
  #   safe_input = policy.apply(raw_params)
  #   sql = Json2sql::SelectRunner.build(safe_input)

  class QueryPolicy

    def initialize(mode: :allow, tables: {})

      @mode = mode

      @tables = Json2sql.normalize(tables)
    end

    # Returns a sanitized copy of input ready to pass to any Runner.
    # Runners remain unmodified — they receive only the clean Hash.

    def apply(input)

      input = Json2sql.normalize(input)
      
      filter_tables(input, @tables)

      input.each { |table, params| sanitize_table(params, @tables[table]) }

      input.reject! { |_, params| empty_columns?(params) }

      input
    end

    private

    def sanitize_table(params, config)

      return unless params.is_a?(Hash)

      return unless config.is_a?(Hash)

      filter_columns(params, config)

      inject_where(params, config)

      %w[children parents].each do |relation|

        filter_relations(params, config, relation)

        next unless params[relation].is_a?(Hash)

        tables = config[relation].is_a?(Hash) ? config[relation] : {}

        params[relation].each { |table, params| sanitize_table(params, tables[table]) }

        params[relation].reject! { |_, params| empty_columns?(params) }

      end
    end

    def empty_columns?(params)

      return false unless params.is_a?(Hash)

      columns = params["columns"]

      (columns.is_a?(Array) || columns.is_a?(Hash)) && columns.empty?
    end

    def filter_tables(params, config)

      return if @mode == :deny

      return unless params.is_a?(Hash)

      tables = config.is_a?(Hash) ? config : {}

      params.select! { |table, _| tables.key?(table) }
    end
    
    # Filters children/parents relations in :allow mode.
    # Only relations present as keys in config[relation] pass through.
    # If config[relation] is absent or not a Hash, all relations are blocked.
    # No-op in :deny mode.

    def filter_relations(params, config, relation)

      return if @mode == :deny

      param_tables = params[relation]

      return unless param_tables.is_a?(Hash)

      config_tables = config[relation]

      params[relation] = config_tables.is_a?(Hash) ? param_tables.select { |table, _| config_tables.key?(table) } : {}
    end

    # Filters "columns" using mode (:allow or :deny).
    # Handles Array (SELECT) and Hash (INSERT/UPDATE) column formats.
    # Hash entries (function columns) always pass through in :allow mode.
    # If no column list is defined: in :allow mode all columns are blocked;
    # in :deny mode columns are untouched.

    def filter_columns(params, config)

      param_columns = params["columns"]

      return unless param_columns.is_a?(Array) || param_columns.is_a?(Hash)

      config_columns = config["columns"]

      unless config_columns.is_a?(Array)

        if @mode == :allow

          params["columns"] = param_columns.is_a?(Array) ? [] : {}
        end

        return
      end

      if @mode == :deny

        if param_columns.is_a?(Array)

          params["columns"] = param_columns.reject { |c| config_columns.include?(c) }

          return
        end

        params["columns"] = param_columns.reject { |k, _| config_columns.include?(k) }

        return
      end

      if param_columns.is_a?(Array)

        params["columns"] = param_columns.select { |c| c.is_a?(Hash) || config_columns.include?(c) }
        
        return
      end

      params["columns"] = param_columns.select { |k, _| config_columns.include?(k) }
    end

    # Merges forced "and" conditions into params["and"].
    # Forced keys overwrite user-supplied values for the same column,
    # preventing IDOR (e.g. attacker cannot override user_id).

    def inject_where(params, config)

      forced_and = config.dig("where", "and")

      return unless forced_and.is_a?(Hash)

      params["and"] ||= {}

      params["and"].merge!(forced_and)
    end

  end
end
