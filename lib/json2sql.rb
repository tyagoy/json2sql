require_relative "json2sql/version"
require_relative "json2sql/sanitizer"
require_relative "json2sql/where_relation"
require_relative "json2sql/where_model"
require_relative "json2sql/select_model"
require_relative "json2sql/select_runner"
require_relative "json2sql/insert_model"
require_relative "json2sql/insert_runner"
require_relative "json2sql/update_model"
require_relative "json2sql/update_runner"
require_relative "json2sql/delete_model"
require_relative "json2sql/delete_runner"
require_relative "json2sql/input_policy"

# Json2sql — SQL builder that generates MySQL/MariaDB query strings from
# plain Ruby Hashes (or parsed JSON).
#
# All Hash keys may be either Strings or Symbols; they are normalized to
# Strings internally before processing.
#
# Entry points:
#   Json2sql::SelectRunner.build(hash) → String
#   Json2sql::InsertRunner.build(hash) → String
#   Json2sql::UpdateRunner.build(hash) → String
#   Json2sql::DeleteRunner.build(hash) → String

module Json2sql

  # Deep-converts all Hash keys to Strings and recurses into nested Hashes
  # and Arrays. Leaves all other values (Integers, Strings, etc.) unchanged.

  def self.normalize(object)

    return object.each_with_object({}) { |(key, value), hash| hash[key.to_s] = normalize(value) } if object.is_a?(Hash)

    return object.map { |value| normalize(value) } if object.is_a?(Array)

    object
  end

end
