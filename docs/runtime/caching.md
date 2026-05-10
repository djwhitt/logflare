# Caching

{{ mod("Logflare.ContextCache") }} is a read-through caching layer built on [Cachex](https://hexdocs.pm/cachex/) that reduces database load for hot paths.

**Design:**

- One cache per context module (e.g., {{ mod("Logflare.Users.Cache") }}, {{ mod("Logflare.Sources.Cache") }})
- Results wrapped in `{:cached, value}` tuples to distinguish cached `nil` from cache miss
- Cache busting via WAL-based invalidation — matches on struct `:id` fields across three patterns (single structs, lists of structs, `{:ok, struct}` tuples)
- Optional `bust_by/1` callback for custom invalidation keys
