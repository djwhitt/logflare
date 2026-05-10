# Log Event Processing

The `Logflare.LogEvent` struct is the core data unit flowing through the system.

## Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID |
| `body` | `map` | Event payload (user data) |
| `event_type` | `:log \| :metric \| :trace` | Classified type |
| `ingested_at` | `utc_datetime_usec` | Server ingestion time |
| `source_uuid` | `Ecto.UUID.Atom` | Immutable source reference |
| `via_rule_id` | `id` | Rule that routed this event |
| `retries` | `integer` | Retry counter for failed inserts |
| `pipeline_error` | `embedded_schema` | Error tracking (stage, type, message) |

## Creation Pipeline

`LogEvent.make/2` runs through these stages for each incoming event:

1. **Mapping** — apply data transformations from source config
2. **Type Detection** — classify as `:log`, `:metric`, or `:trace` (during struct construction)
3. **Transformation** — field enrichment (copy fields, KV enrichment)
4. **Validation** — structural and content validation

## Type Detection

`Logflare.LogEvent.TypeDetection` classifies events using a two-pass strategy:

1. **Explicit metadata** — if `metadata.type` is set (e.g., by OTEL processors), use it directly
2. **Heuristic detection** — inspect body keys:
   - **Trace**: has `trace_id` AND `span_id` AND (`parent_span_id` OR `start_time` OR `duration`)
   - **Metric**: has `metric_type`/`metric` AND `value`/`gauge`/`count`/`sum`
   - **Log**: default fallback

The event type determines routing in backend adaptors (e.g., ClickHouse routes to type-specific OTEL tables).
