# json2sql

Pure-Ruby SQL builder. Translates Ruby Hashes (or parsed JSON) into MySQL/MariaDB query strings. No runtime dependencies. No gem packaging — use via `require_relative` or `$LOAD_PATH`.

## Build and Test

```bash
ruby -Ilib test/json2sql_test.rb
```

No Bundler, no Rake, no gemspec. Just Ruby + Minitest (stdlib).

## Architecture

```
lib/json2sql.rb          # module Json2sql + normalize helper
  sanitizer.rb           # stateless string-escaping utilities
  where_relation.rb      # JOIN/nesting relationship (none / child / parent)
  where_model.rb         # WHERE clause builder
  select_model.rb        # SELECT body, JSON wrappers, recursive nesting
  select_runner.rb       # public entry point: Json2sql::SelectRunner.build(h)
  insert_model.rb / insert_runner.rb
  update_model.rb / update_runner.rb
  delete_model.rb / delete_runner.rb
```

**Runner → Model pattern**: every operation has a paired `*_runner.rb` (public API, stateless `.build` class method) and `*_model.rb` (internal assembler, instantiated per table).

## Conventions

- **String mutation**: all SQL is built by mutating a single unfrozen `+""` string via `<<`. Never use `String#+` or interpolation in hot paths.
- **Separator flag**: a boolean `@sep`/`separator` is used everywhere to avoid leading/trailing commas — follow this pattern in new conditions or column lists.
- **`"columns"` key is polymorphic**: Array for SELECT (column list), Hash for INSERT/UPDATE (`column => value` map).
- **WHERE conditions live under `"and"` / `"or"`**: there is no `"where"` wrapper key despite comments in older code.
- **String keys and Symbol keys are both accepted** — normalized internally via `Json2sql.normalize`.

## Key Pitfalls

- **No boolean equality**: use integer `1`/`0`. `true`/`false` only works with the `"null"` action.
- **`LATERAL` requires MySQL 8.0+ / MariaDB 10.9+**: all SELECT output uses `FROM LATERAL (…)`.
- **`"options" => ["total"]` runs two subqueries**: one `JSON_ARRAYAGG` and one `COUNT(*)`. Needs proper indexes on large tables.
- **Empty `IN` array emits `IN (NULL)`**: effectively always false — intentional guard, not a bug.
- **Identifier sanitizer strips but does not reject**: bad input like `"users; DROP TABLE"` becomes `"usersDROPTABLE"` — mangled but not executed.
- **`@sep` is shared instance state** across `build_columns_json`, `build_columns_array`, `build_columns_object`. Call them in that declared order within one build cycle.

## WHERE Operators (implicit and explicit)

| Value type | Implicit behavior |
|---|---|
| `Integer` | `=` |
| `String` | `LIKE '%v%'` (contains) |

Explicit operators: `=`, `<`, `>`, `<=`, `>=`, `!=`, `<>`, `in`, `!in`, `like`, `!like`, `first` (`v%`), `last` (`%v`), `contains` (`%v%`), `null` (IS NULL / IS NOT NULL).

Column cross-references use `"$.table.col"` JSON-path syntax; resolved by `Sanitizer.reference`.
