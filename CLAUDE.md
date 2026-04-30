# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bundle exec rake test     # run full test suite (default task)
bundle exec rake build    # build .gem to pkg/
bundle exec rake release  # tag + push + publish to RubyGems.org

# Run a single test file directly
ruby -Ilib test/json2sql_test.rb
```

## Architecture

**json2sql** is a pure-Ruby SQL builder (zero runtime dependencies) that converts Ruby Hashes into MySQL/MariaDB query strings. Target: MySQL 8.0+ / MariaDB 10.9+ (uses `LATERAL` subqueries and `JSON_*` functions).

### Runner → Model pattern

Every operation has a paired Runner and Model class:

- **Runner** (`*_runner.rb`): public API, single stateless `.build(hash)` class method. Calls `Json2sql.normalize()` to deep-convert all keys to Strings, then delegates to the Model.
- **Model** (`*_model.rb`): instantiated per table, mutates a shared `sql` string passed by reference via `<<`. Never uses `String#+` or interpolation in hot paths.

The four entry points:
```ruby
Json2sql::SelectRunner.build(hash)  # → SELECT JSON_OBJECT(…)
Json2sql::InsertRunner.build(hash)  # → INSERT INTO …
Json2sql::UpdateRunner.build(hash)  # → UPDATE … SET …
Json2sql::DeleteRunner.build(hash)  # → DELETE FROM …
```

### Key supporting classes

- **`Sanitizer`** — stateless string-escaping utilities. `keyword()` strips dangerous chars from identifiers (allows only `[a-zA-Z0-9_-]`). `value()` escapes single quotes (doubled) and backslashes. `reference("$.table.col")` converts JSON-path syntax to `` `table`.`col` `` SQL syntax.
- **`WhereModel`** — assembles WHERE clauses. Dispatches by Ruby type: `Integer` → implicit `=`, `String` → implicit `LIKE '%value%'`, `Hash` → explicit operator. Handles nested `"and"`/`"or"` groups recursively.
- **`WhereRelation`** — enum + builder for relationship types (`NONE`, `CHILD`, `PARENT`). Derives foreign key names from table names (e.g. `users` → `user_id`, `categories` → `category_id`). Used by WhereModel to emit JOIN conditions in nested queries.

### Conventions

- **String mutation**: SQL is built by appending to a single unfrozen `+""` string via `<<`.
- **Separator flag**: A boolean `glue`/`separator` flag (starts `false`, set `true` after first item) prevents leading commas in all list-building loops.
- **Polymorphic `"columns"` key**: Array for SELECT (list of column names); Hash for INSERT/UPDATE (column → value mapping).
- **WHERE conditions** live under `"and"` or `"or"` keys — there is no `"where"` wrapper key.
- **Nested relations**: `"children"` key for one-to-many (produces `JSON_ARRAYAGG`), `"parents"` key for many-to-one (produces `JSON_OBJECT`). Nesting is recursive.

### SELECT output shape

```sql
SELECT JSON_OBJECT(
  'table1', (SELECT JSON_ARRAYAGG(JSON_OBJECT(...)) FROM LATERAL (...)),
  'table2', (SELECT JSON_OBJECT(...) FROM LATERAL (...))
);
```

`"options" => ["total"]` wraps the result in `{ "data": […], "total": N }` by running an additional `COUNT(*)` subquery — doubles query cost.

### Pitfalls

- No boolean equality — use `1`/`0`. `true`/`false` is only valid with the `"null"` operator (IS NULL / IS NOT NULL).
- Empty `"in"` array emits `IN (NULL)` — always false, intentional.
- Malformed identifiers are mangled but not dangerous: `"users; DROP TABLE"` → `` `usersDROPTABLE` ``.
