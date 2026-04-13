# frozen_string_literal: true

require_relative "lib/json2sql/version"

Gem::Specification.new do |spec|
  spec.name          = "json2sql"
  spec.version       = Json2sql::VERSION
  spec.authors       = ["Tiago da Silva"]
  spec.email         = ["tyagoy@gmail.com"]
  spec.summary       = "Translates Ruby Hashes (or parsed JSON) into MySQL/MariaDB query strings."
  spec.description   = "Pure-Ruby SQL builder. No runtime dependencies. Supports SELECT (with JSON aggregation and nesting), INSERT, UPDATE, and DELETE for MySQL/MariaDB."
  spec.homepage      = "https://github.com/tyagoy/json2sql"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.7"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir["lib/**/*.rb"] + ["LICENSE.txt"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake",     "~> 13.0"
end
