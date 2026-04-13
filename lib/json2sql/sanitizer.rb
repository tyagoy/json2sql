module Json2sql
  module Sanitizer
    # Characters stripped from SQL identifiers (table/column names).
    KEYWORD_DANGEROUS = /[ `;"'\\]/

    # Removes dangerous characters from an identifier string.
    def self.keyword(input)
      input.to_s.gsub(KEYWORD_DANGEROUS, "")
    end

    # Escapes a value string for safe embedding between SQL quotes.
    # ' → ''   and   \ → \\
    def self.value(input)
      input.to_s.gsub("\\", "\\\\\\\\").gsub("'", "''")
    end

    # Wraps an identifier in the given quote character (default: backtick).
    # Dangerous characters inside the identifier are stripped.
    def self.keyword_wrap(input, wrap = "`")
      "#{wrap}#{keyword(input)}#{wrap}"
    end

    # Wraps a value in the given quote character (default: single-quote).
    # Single quotes and backslashes inside the value are escaped.
    def self.value_wrap(input, wrap = "'")
      "#{wrap}#{value(input)}#{wrap}"
    end

    # Converts a JSON path reference (e.g. "$.users.id") into a
    # backtick-quoted SQL reference (e.g. "`users`.`id`").
    # Strips the leading "$." and splits on ".".
    def self.reference(input)
      str = input.to_s[2..] # strip leading "$."
      result = +"`"
      str.each_char do |c|
        case c
        when "."
          result << "`.`"
        when " ", "`", ";", '"', "'", "\\"
          # skip dangerous characters
        else
          result << c
        end
      end
      result << "`"
      result
    end
  end
end
