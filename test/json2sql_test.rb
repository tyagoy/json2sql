# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/json2sql"

# ---------------------------------------------------------------------------
# Sanitizer
# ---------------------------------------------------------------------------
class SanitizerTest < Minitest::Test
  def test_keyword_wrap
    assert_equal "`users`", Json2sql::Sanitizer.keyword_wrap("users")
  end

  def test_keyword_wrap_custom_quote
    assert_equal "'users'", Json2sql::Sanitizer.keyword_wrap("users", "'")
  end

  def test_keyword_strips_dangerous_chars
    assert_equal "`dropdrop`", Json2sql::Sanitizer.keyword_wrap("drop; drop")
    assert_equal "`col`",      Json2sql::Sanitizer.keyword_wrap("co`l")
    assert_equal "`col`",      Json2sql::Sanitizer.keyword_wrap("col'")
    assert_equal "`col`",      Json2sql::Sanitizer.keyword_wrap("col\"")
  end

  def test_value_wrap_escapes_single_quote
    assert_equal "'O''Brien'", Json2sql::Sanitizer.value_wrap("O'Brien")
  end

  def test_value_wrap_escapes_backslash
    assert_equal "'a\\\\b'", Json2sql::Sanitizer.value_wrap('a\b')
  end

  def test_reference_simple
    assert_equal "`user_id`", Json2sql::Sanitizer.reference("$.user_id")
  end

  def test_reference_dotted
    assert_equal "`users`.`id`", Json2sql::Sanitizer.reference("$.users.id")
  end
end

# ---------------------------------------------------------------------------
# WhereRelation
# ---------------------------------------------------------------------------
class WhereRelationTest < Minitest::Test
  def test_build_table_id_plural
    r = Json2sql::WhereRelation.none("x")
    assert_equal "`user_id`",     r.build_table_id("users")
    assert_equal "`admin_id`",    r.build_table_id("admins")
  end

  def test_build_table_id_ies
    r = Json2sql::WhereRelation.none("x")
    assert_equal "`category_id`", r.build_table_id("categories")
    assert_equal "`entry_id`",    r.build_table_id("entries")
  end

  def test_build_table_id_no_suffix
    r = Json2sql::WhereRelation.none("x")
    assert_equal "`tag_id`", r.build_table_id("tag")
  end

  def test_child_relation
    r   = Json2sql::WhereRelation.child("posts")
    sql = +""
    r.build_table_relation(sql, "comments")
    assert_equal "`posts`.`comment_id` = `comments`.`id`", sql
  end

  def test_parent_relation
    r   = Json2sql::WhereRelation.parent("users")
    sql = +""
    r.build_table_relation(sql, "posts")
    assert_equal "`posts`.`user_id` = `users`.`id`", sql
  end
end

# ---------------------------------------------------------------------------
# SelectRunner
# ---------------------------------------------------------------------------
class SelectRunnerTest < Minitest::Test
  def test_basic_select
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id", "name"] }
    )
    assert_match(/SELECT JSON_OBJECT\(/, sql)
    assert_match(/JSON_ARRAYAGG\(JSON_OBJECT\(/, sql)
    assert_match(/'id', `users`\.`id`/, sql)
    assert_match(/'name', `users`\.`name`/, sql)
  end

  def test_symbol_keys_accepted
    sql = Json2sql::SelectRunner.build(
      users: { columns: ["id"] }
    )
    assert_match(/FROM.*`users`/, sql)
  end

  def test_where_equality
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "id" => 5 } }
    )
    assert_match(/WHERE \(`users`\.`id` = 5\)/, sql)
  end

  def test_where_like_string
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "name" => "john" } }
    )
    assert_match(/`users`\.`name` LIKE '%john%'/, sql)
  end

  def test_where_in_array
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "status" => { "in" => [1, 2, 3] } } }
    )
    assert_match(/`users`\.`status` IN \(1, 2, 3\)/, sql)
  end

  def test_where_not_in_array
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "role" => { "!in" => [9, 10] } } }
    )
    assert_match(/NOT IN \(9, 10\)/, sql)
  end

  def test_where_is_null
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "deleted_at" => { "null" => true } } }
    )
    assert_match(/`users`\.`deleted_at` IS NULL/, sql)
  end

  def test_where_is_not_null
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "deleted_at" => { "null" => false } } }
    )
    assert_match(/`users`\.`deleted_at` IS NOT NULL/, sql)
  end

  def test_where_gte
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "age" => { ">=" => 18 } } }
    )
    assert_match(/`users`\.`age` >= 18/, sql)
  end

  def test_where_float
    sql = Json2sql::SelectRunner.build(
      "products" => { "columns" => ["id"], "and" => { "price" => { ">=" => 9.99 } } }
    )
    assert_match(/`products`\.`price` >= 9.99/, sql)
  end

  def test_where_like_operator
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "email" => { "like" => "%.com" } } }
    )
    assert_match(/`users`\.`email` LIKE '%.com'/, sql)
  end

  def test_where_like_first
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "name" => { "first" => "Jo" } } }
    )
    assert_match(/LIKE 'Jo%'/, sql)
  end

  def test_where_like_last
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "name" => { "last" => "son" } } }
    )
    assert_match(/LIKE '%son'/, sql)
  end

  def test_where_reference
    sql = Json2sql::SelectRunner.build(
      "posts" => { "columns" => ["id"], "and" => { "author_id" => { "=" => "$.users.id" } } }
    )
    assert_match(/`posts`\.`author_id` = `users`\.`id`/, sql)
  end

  def test_where_string_equals
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "email" => { "=" => "a@b.com" } } }
    )
    assert_match(/`users`\.`email` = 'a@b.com'/, sql)
  end

  def test_where_or
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "or" => { "id" => 1 } }
    )
    assert_match(/WHERE \(`users`\.`id` = 1\)/, sql)
  end

  def test_order
    sql = Json2sql::SelectRunner.build(
      "users" => {
        "columns" => ["id"],
        "order"   => { "created_at" => "desc", "name" => "asc" }
      }
    )
    assert_match(/ORDER BY `users`\.`created_at` DESC, `users`\.`name` ASC/, sql)
  end

  def test_limit_and_offset
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "limit" => 10, "offset" => 20 }
    )
    assert_match(/LIMIT 10/, sql)
    assert_match(/OFFSET 20/, sql)
  end

  def test_options_total
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "options" => ["total"] }
    )
    assert_match(/'data'/, sql)
    assert_match(/'total'/, sql)
    assert_match(/COUNT\(\*\)/, sql)
  end

  def test_no_options_no_total
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"] }
    )
    refute_match(/COUNT\(\*\)/, sql)
  end

  def test_multiple_tables
    sql = Json2sql::SelectRunner.build(
      "users"    => { "columns" => ["id"] },
      "products" => { "columns" => ["id"] }
    )
    assert_match(/'users'/, sql)
    assert_match(/'products'/, sql)
  end

  def test_sql_injection_in_table_name_is_sanitized
    # Semicolons and spaces are stripped from identifiers, making the
    # injected payload a harmless concatenated word, not executable SQL.
    sql = Json2sql::SelectRunner.build(
      "users; DROP TABLE users--" => { "columns" => ["id"] }
    )
    # The only ; in the output is the statement terminator at the very end
    assert_equal 1, sql.count(";")
    assert_match(/usersDROPTABLEusers--/, sql)
  end

  def test_sql_injection_in_column_name_is_sanitized
    # Semicolons and spaces are stripped, so the injection payload cannot
    # be executed. Letters remain but form a single mangled identifier.
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id; DROP TABLE users--"] }
    )
    # Only the trailing statement terminator ; remains
    assert_equal 1, sql.count(";")
    assert_match(/idDROPTABLEusers--/, sql)
  end

  def test_sql_injection_in_value_is_escaped
    # The single quote in the value is doubled (SQL escape), so the
    # payload ends up as a safe string literal — not executable SQL.
    # The text may still appear inside the quoted string, which is fine.
    sql = Json2sql::SelectRunner.build(
      "users" => { "columns" => ["id"], "and" => { "name" => { "=" => "'; DROP TABLE users--" } } }
    )
    # The value must be wrapped in quotes and contain the escaped quote
    assert_match(/''; DROP TABLE users--'/, sql)
    # No unquoted semicolon outside string literals
    refute_match(/[^']; DROP/, sql)
  end

  def test_nested_children
    sql = Json2sql::SelectRunner.build(
      "users" => {
        "columns"  => ["id", "name"],
        "children" => {
          "posts" => { "columns" => ["id", "title"] }
        }
      }
    )
    assert_match(/'posts'/, sql)
    assert_match(/`posts`.`user_id` = `users`.`id`/, sql)
  end

  def test_nested_parents
    sql = Json2sql::SelectRunner.build(
      "posts" => {
        "columns" => ["id", "title"],
        "parents" => {
          "users" => { "columns" => ["id", "name"] }
        }
      }
    )
    assert_match(/'users'/, sql)
    assert_match(/`posts`.`user_id` = `users`.`id`/, sql)
  end

  def test_ends_with_semicolon_and_newline
    sql = Json2sql::SelectRunner.build("users" => { "columns" => ["id"] })
    assert sql.end_with?(";\n"), "Expected SQL to end with ;\\n, got: #{sql[-5..]}"
  end
end

# ---------------------------------------------------------------------------
# InsertRunner
# ---------------------------------------------------------------------------
class InsertRunnerTest < Minitest::Test
  def test_single_insert
    sql = Json2sql::InsertRunner.build(
      "users" => { "columns" => { "name" => "John", "age" => 30 } }
    )
    assert_match(/INSERT INTO `users`/, sql)
    assert_match(/`name`, `age`/, sql)
    assert_match(/'John', 30/, sql)
  end

  def test_insert_float
    sql = Json2sql::InsertRunner.build(
      "products" => { "columns" => { "price" => 9.99 } }
    )
    assert_match(/9.99/, sql)
  end

  def test_insert_escapes_single_quote
    sql = Json2sql::InsertRunner.build(
      "users" => { "columns" => { "name" => "O'Brien" } }
    )
    assert_match(/'O''Brien'/, sql)
  end

  def test_bulk_insert
    sql = Json2sql::InsertRunner.build(
      "tags" => [
        { "columns" => { "name" => "ruby" } },
        { "columns" => { "name" => "rails" } }
      ]
    )
    assert_equal 2, sql.scan(/INSERT INTO/).count
    assert_match(/'ruby'/, sql)
    assert_match(/'rails'/, sql)
  end

  def test_each_insert_ends_with_semicolon
    sql = Json2sql::InsertRunner.build(
      "tags" => [
        { "columns" => { "name" => "a" } },
        { "columns" => { "name" => "b" } }
      ]
    )
    assert_equal 2, sql.scan(/;/).count
  end
end

# ---------------------------------------------------------------------------
# UpdateRunner
# ---------------------------------------------------------------------------
class UpdateRunnerTest < Minitest::Test
  def test_basic_update
    sql = Json2sql::UpdateRunner.build(
      "users" => {
        "columns" => { "name" => "Jane" },
        "and"     => { "id" => 42 }
      }
    )
    assert_match(/UPDATE `users` SET/, sql)
    assert_match(/`users`\.`name` = 'Jane'/, sql)
    assert_match(/WHERE \(`users`\.`id` = 42\)/, sql)
  end

  def test_update_integer_column
    sql = Json2sql::UpdateRunner.build(
      "users" => { "columns" => { "score" => 100 }, "and" => { "id" => 1 } }
    )
    assert_match(/`users`\.`score` = 100/, sql)
  end

  def test_update_float_column
    sql = Json2sql::UpdateRunner.build(
      "products" => { "columns" => { "price" => 4.5 }, "and" => { "id" => 1 } }
    )
    assert_match(/`products`\.`price` = 4.5/, sql)
  end

  def test_bulk_update
    sql = Json2sql::UpdateRunner.build(
      "settings" => [
        { "columns" => { "value" => "dark" },  "and" => { "key" => { "=" => "theme" } } },
        { "columns" => { "value" => "en" },    "and" => { "key" => { "=" => "lang"  } } }
      ]
    )
    assert_equal 2, sql.scan(/UPDATE/).count
  end
end

# ---------------------------------------------------------------------------
# DeleteRunner
# ---------------------------------------------------------------------------
class DeleteRunnerTest < Minitest::Test
  def test_basic_delete
    sql = Json2sql::DeleteRunner.build(
      "users" => { "and" => { "id" => 42 } }
    )
    assert_match(/DELETE FROM `users`/, sql)
    assert_match(/WHERE \(`users`\.`id` = 42\)/, sql)
  end

  def test_delete_with_like
    sql = Json2sql::DeleteRunner.build(
      "sessions" => { "and" => { "token" => { "like" => "expired_%" } } }
    )
    assert_match(/DELETE FROM `sessions`/, sql)
    assert_match(/LIKE 'expired_%'/, sql)
  end

  def test_bulk_delete
    sql = Json2sql::DeleteRunner.build(
      "sessions" => [
        { "and" => { "user_id" => 1 } },
        { "and" => { "user_id" => 2 } }
      ]
    )
    assert_equal 2, sql.scan(/DELETE FROM/).count
  end
end
