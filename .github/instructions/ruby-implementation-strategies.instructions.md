---
description: "Use when writing or reviewing Ruby code in this project. Covers preferred implementation strategies: early return, guard clauses, and buffer-based SQL building."
applyTo: "**/*.rb"
---

# Ruby Implementation Strategies

## Early Return

Prefer early return / guard clauses at the top of methods to reduce nesting. Exit as soon as a precondition is not met.

```ruby
# preferred
def build(params)
  return unless valid?(params)
  # ... main logic
end

# avoid
def build(params)
  if valid?(params)
    # ... main logic
  end
end
```

Apply at every level: methods, blocks, case branches. Use `next` inside loops and `return` inside methods.

## Guard Clauses Over Nested Conditionals

Collapse multi-level `if/else` trees into a flat sequence of guards. Each guard handles one failure case and returns immediately.

```ruby
# preferred
def process(value, column, action)
  return if value.nil?
  return emit_null(column) if action == "null"
  emit_comparison(value, column, action)
end

# avoid
def process(value, column, action)
  if !value.nil?
    if action == "null"
      emit_null(column)
    else
      emit_comparison(value, column, action)
    end
  end
end
```


