module Json2sql

  # Sanitizes a query input Hash before passing it to any Runner.
  #
  # Parameters:
  #   mode:   :allow (default) — only tables listed in `tables:` are accessible.
  #                              Tables absent from `tables:` are blocked entirely.
  #                              Empty `tables:` = no restriction.
  #           :deny            — all tables pass; only listed columns are stripped.
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
  #   policy = Json2sql::InputPolicy.new(
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

      input.each { |table, params| sanitize_table(params, @tables[table] || {}) }

      input
    end

    private

    def filter_tables(input)

      return input if @mode == :deny || @tables.empty?

      input.select { |table, _| @tables.key?(table) }
    end

    def sanitize_table(params, config)

      return unless params.is_a?(Hash)

      filter_columns(params, config)

      inject_where(params, config)

      %w[children parents].each do |relation|

        if @mode == :deny

          next unless params[relation].is_a?(Hash)

          relation_configs = config[relation].is_a?(Hash) ? config[relation] : {}

          params[relation].each { |child_table, child_params| sanitize_table(child_params, relation_configs[child_table] || {}) }

          params[relation].reject! { |_, child_params| child_params.is_a?(Hash) && child_params["columns"].is_a?(Array) && child_params["columns"].empty? }

        else

          filter_relations(params, config, relation)

          next unless params[relation].is_a?(Hash)

          relation_configs = config[relation].is_a?(Hash) ? config[relation] : {}

          params[relation].each { |child_table, child_params| sanitize_table(child_params, relation_configs[child_table] || {}) }

        end
      end
    end

    # Filters children/parents relations in :allow mode.
    # Only relations present as keys in config[relation_key] pass through.
    # If config[relation_key] is absent or not a Hash, relations are untouched.
    # In :deny mode, pruning is handled in sanitize_table after column filtering.

    def filter_relations(params, config, relation_key)

      relations = params[relation_key]

      return unless relations.is_a?(Hash)

      relation_config = config[relation_key]

      return unless relation_config.is_a?(Hash)

      params[relation_key] = relations.select { |t, _| relation_config.key?(t) }
    end

    # Filters "columns" using mode (:allow or :deny).
    # Handles Array (SELECT) and Hash (INSERT/UPDATE) column formats.
    # Hash entries (function columns) always pass through in :allow mode.
    # If no column list is defined for the table, columns are untouched.

    def filter_columns(params, config)

      columns = params["columns"]

      return unless columns.is_a?(Array) || columns.is_a?(Hash)

      list = config["columns"]

      return unless list.is_a?(Array)

      params["columns"] = if @mode == :deny

        columns.is_a?(Array) ? columns.reject { |c| list.include?(c) } : columns.reject { |k, _| list.include?(k) }

      else

        columns.is_a?(Array) ? columns.select { |c| c.is_a?(Hash) || list.include?(c) } : columns.select { |k, _| list.include?(k) }

      end
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
