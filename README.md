# json2sql

Pure-Ruby SQL builder. Translates Ruby Hashes (or parsed JSON) into MySQL/MariaDB query strings.

- No runtime dependencies
- String and Symbol keys are both accepted
- Target: MySQL 8.0+ / MariaDB 10.9+

## Installation

```bash
gem install json2sql
```

Or in your Gemfile:

```ruby
gem "json2sql"
```

## Usage

```ruby
require "json2sql"
```

All entry points are stateless class methods that return a SQL string.

---

## SELECT

```ruby
Json2sql::SelectRunner.build(hash) → String
```

The result is always a `SELECT JSON_OBJECT(…)` query. Multiple top-level keys produce multiple named subqueries wrapped in a single outer `JSON_OBJECT`.

### Basic

```ruby
Json2sql::SelectRunner.build(
  "users" => { "columns" => ["id", "name", "email"] }
)
```

### WHERE conditions

Conditions live under the `"and"` or `"or"` key.

```ruby
Json2sql::SelectRunner.build(
  "users" => {
    "columns" => ["id", "name"],
    "and" => {
      "active" => 1,       # Integer → col = 1
      "name"   => "john",  # String  → col LIKE '%john%'
    }
  }
)
```

#### Explicit operators

| Key | SQL |
|---|---|
| `{ "=" => value }` | `col = value` |
| `{ "!=" => value }` or `{ "<>" => value }` | `col != value` |
| `{ ">" => value }` | `col > value` |
| `{ ">=" => value }` | `col >= value` |
| `{ "<" => value }` | `col < value` |
| `{ "<=" => value }` | `col <= value` |
| `{ "in" => [1, 2, 3] }` | `col IN (1, 2, 3)` |
| `{ "!in" => [1, 2] }` | `col NOT IN (1, 2)` |
| `{ "like" => "%.com" }` | `col LIKE '%.com'` |
| `{ "!like" => "%.com" }` | `col NOT LIKE '%.com'` |
| `{ "contains" => "john" }` | `col LIKE '%john%'` |
| `{ "first" => "Jo" }` | `col LIKE 'Jo%'` |
| `{ "last" => "son" }` | `col LIKE '%son'` |
| `{ "null" => true }` | `col IS NULL` |
| `{ "null" => false }` | `col IS NOT NULL` |

```ruby
Json2sql::SelectRunner.build(
  "users" => {
    "columns" => ["id", "name"],
    "and" => {
      "age"        => { ">=" => 18 },
      "role"       => { "!in" => [0, 9] },
      "deleted_at" => { "null" => true },
      "email"      => { "last" => ".com" }
    }
  }
)
```

#### Column cross-references

Use `"$.table.column"` syntax to reference another column instead of a literal value:

```ruby
"and" => { "author_id" => { "=" => "$.users.id" } }
# → `posts`.`author_id` = `users`.`id`
```

#### Nested AND / OR

```ruby
"and" => {
  "active" => 1,
  "or" => { "role" => 1, "admin" => 1 }
}
```

### ORDER BY

```ruby
"order" => { "created_at" => "desc", "name" => "asc" }
```

### LIMIT and OFFSET

```ruby
"limit" => 20, "offset" => 40
```

### Total count (`options`)

Adding `"options" => ["total"]` wraps the result in `{ "data": […], "total": N }` by running an additional `COUNT(*)` subquery.

```ruby
Json2sql::SelectRunner.build(
  "users" => {
    "columns" => ["id", "name"],
    "and"     => { "active" => 1 },
    "order"   => { "created_at" => "desc" },
    "limit"   => 20,
    "offset"  => 0,
    "options" => ["total"]
  }
)
```

### Nested children (one-to-many)

```ruby
Json2sql::SelectRunner.build(
  "users" => {
    "columns"  => ["id", "name"],
    "children" => {
      "posts" => { "columns" => ["id", "title"] }
    }
  }
)
# JOIN condition: `posts`.`user_id` = `users`.`id`
```

### Nested parents (many-to-one)

```ruby
Json2sql::SelectRunner.build(
  "posts" => {
    "columns" => ["id", "title"],
    "parents" => {
      "users" => { "columns" => ["id", "name"] }
    }
  }
)
# JOIN condition: `posts`.`user_id` = `users`.`id`
```

Nesting is recursive — children can have their own children.

### Multiple tables

```ruby
Json2sql::SelectRunner.build(
  "users"    => { "columns" => ["id", "name"] },
  "products" => { "columns" => ["id", "price"] }
)
# → SELECT JSON_OBJECT('users', (…), 'products', (…));
```

---

## INSERT

```ruby
Json2sql::InsertRunner.build(hash) → String
```

`"columns"` is a **Hash** of `column => value`.

### Single row

```ruby
Json2sql::InsertRunner.build(
  "users" => { "columns" => { "name" => "João", "email" => "joao@example.com" } }
)
# → INSERT INTO `users` (`name`, `email`) VALUES ('João', 'joao@example.com');
```

### Multiple rows

Pass an Array of row hashes:

```ruby
Json2sql::InsertRunner.build(
  "tags" => [
    { "columns" => { "name" => "ruby" } },
    { "columns" => { "name" => "rails" } }
  ]
)
# → INSERT INTO `tags` (`name`) VALUES ('ruby');
#   INSERT INTO `tags` (`name`) VALUES ('rails');
```

---

## UPDATE

```ruby
Json2sql::UpdateRunner.build(hash) → String
```

```ruby
Json2sql::UpdateRunner.build(
  "users" => {
    "columns" => { "name" => "Maria", "active" => 1 },
    "and"     => { "id" => 42 }
  }
)
# → UPDATE `users` SET `users`.`name` = 'Maria', `users`.`active` = 1 WHERE (`users`.`id` = 42);
```

---

## DELETE

```ruby
Json2sql::DeleteRunner.build(hash) → String
```

```ruby
Json2sql::DeleteRunner.build(
  "users" => { "and" => { "id" => 42 } }
)
# → DELETE FROM `users` WHERE (`users`.`id` = 42);
```

---

## Value types

| Ruby type | SQL output |
|---|---|
| `Integer` | raw number |
| `Float` | raw number |
| `String` | `'escaped value'` |

Single quotes in strings are doubled (`O'Brien` → `'O''Brien'`). Backslashes are escaped.

## Security

Table and column names are sanitized by stripping characters outside `[a-zA-Z0-9_-]`. Malformed identifiers become mangled but harmless (e.g. `"users; DROP TABLE"` → `` `usersDROPTABLE` ``). Values are always wrapped in quoted literals.

## Pitfalls

- **No boolean equality** — use `1`/`0`. `true`/`false` only works with the `"null"` operator.
- **`"options" => ["total"]` doubles query cost** — runs two subqueries. Ensure proper indexes.
- **Empty `in` array emits `IN (NULL)`** — always false, intentional.
- **`LATERAL` subqueries** — requires MySQL 8.0+ or MariaDB 10.9+.

## Development

```bash
bundle exec rake test     # run test suite
bundle exec rake build    # build .gem to pkg/
bundle exec rake release  # tag + push + publish to RubyGems.org
```

## License

[MIT](LICENSE.txt)
