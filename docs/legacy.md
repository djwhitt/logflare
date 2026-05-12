# Legacy and Deprecated Areas

A running list of areas in the codebase that are either older patterns the team has moved away from or explicitly slated for removal. Treat this as the canonical place to check before extending or relying on anything listed here — preference is to migrate callers off these surfaces, not to grow them.

This page is hand-maintained. If you spot an item that should be added or removed, edit it directly.

## Legacy patterns (still in use)

These work, ship in production, and aren't going away tomorrow — but the team considers them old patterns. New code should use the modern equivalents and existing code should migrate opportunistically rather than by big-bang rewrite.

### Per-source GenServers under `SourceSup`

{{ mod("Logflare.Backends.SourceSup") }} hosts a small zoo of per-source workers that predate the {{ mod("Logflare.Backends") }} / `Adaptor` / Broadway pipeline architecture. They live under {{ src("lib/logflare/sources/source/") }} and are started one-per-source as part of the [`SourceSup` tree](runtime/index.md#per-source-sourcesup):

| Module | Role |
|--------|------|
| {{ mod("Logflare.Sources.Source.RateCounterServer") }} | Per-source rate sampling for the dashboard |
| {{ mod("Logflare.Sources.Source.EmailNotificationServer") }} | Email alerts on log volume |
| {{ mod("Logflare.Sources.Source.TextNotificationServer") }} | SMS alerts |
| {{ mod("Logflare.Sources.Source.WebhookNotificationServer") }} | Generic webhook notifications |
| {{ mod("Logflare.Sources.Source.SlackHookServer") }} | Slack-flavored webhook notifications |
| {{ mod("Logflare.Sources.Source.BillingWriter") }} | Per-source usage counter writes for billing |

Why they're considered legacy:

- One GenServer per source per feature scales linearly with source count, multiplied by the number of features. The modern path centralizes shared concerns at the cluster level (telemetry pollers, `PubSubRates`, etc.) rather than per source.
- Notification fan-out duplicates what a [Backend Adaptor](pipelines/index.md#available-adaptors) (Webhook, Slack-style) can do via the same Broadway path everything else uses. The notification servers exist because they predate that capability.
- Cross-cutting state (rate counters, billing) is a better fit for cluster-wide aggregation than per-source workers polling counters.

The newer additions on the same supervisor — {{ mod("Logflare.Backends.RecentInsertsCacher") }} and {{ mod("Logflare.Backends.SourceSupWorker") }} — are not legacy.

### Per-source BigQuery pipeline wrapping

The BigQuery adaptor doesn't yet implement Broadway directly. {{ mod("Logflare.Backends.Adaptor.BigQueryAdaptor") }} starts a {{ mod("Logflare.Backends.DynamicPipeline") }} that wraps the older {{ mod("Logflare.Sources.Source.BigQuery.Pipeline") }} and {{ mod("Logflare.Sources.Source.BigQuery.Schema") }} modules — an integration shim that lets the legacy per-source modules participate in the new dynamic-scaling supervisor (see the [Available Adaptors](pipelines/index.md#available-adaptors) note). The shim is the long-term migration path; the wrapped modules are the legacy half.

## Slated for deprecation / removal

Items here are explicitly planned to go away. New code must not depend on them, and existing usage should be removed where possible.

### SQL dialect translation (BigQuery → PostgreSQL)

{{ mod("Logflare.Sql.DialectTranslation") }} (called via `Logflare.Sql.translate/4`) translates BigQuery SQL into a PostgreSQL-compatible form so the same endpoint SQL can run against either backend. It is the only consumer of `Sql.translate/4` and is invoked from {{ mod("Logflare.Backends.Adaptor.PostgresAdaptor") }} (`postgres_adaptor.ex:174`).

The translator carries a four-pass AST rewrite plus string-level cleanup — function-by-function `regexp_contains → ~`, `countif → count(*) FILTER`, JSONB cast workarounds, parameter renumbering, and so on. The cost of keeping it correct grows with every BigQuery feature an endpoint uses. Going forward, PostgreSQL endpoints should be authored as PostgreSQL queries from the start (`:pg_sql`); the translator should not gain new function mappings.

See: [SQL Parsing → Dialect Translation](query/sql.md#dialect-translation-bigquery-postgresql).

### Elastic backend adaptor

{{ mod("Logflare.Backends.Adaptor.ElasticAdaptor") }} ({{ src("lib/logflare/backends/adaptor/elastic_adaptor.ex") }}) ships log events to Elasticsearch via the [Filebeat HTTP input](https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-input-http_endpoint.html). It is layered on top of {{ mod("Logflare.Backends.Adaptor.WebhookAdaptor") }} and adds little beyond basic-auth headers and Filebeat's expected envelope. It is slated for removal — users who need Elasticsearch ingest can configure the Webhook adaptor directly.
