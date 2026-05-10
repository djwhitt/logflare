# Code Layout

A directory-level map of the repository, linked to the architecture pages where each area is explained in depth. Path links go to the source on the fork.

## Top-level directories

| Path | Contents |
|---|---|
| {{ src("lib/") }} | All Elixir application code |
| {{ src("native/") }} | Rust NIFs (see [Rust NIFs](runtime/rust-nifs.md)) |
| {{ src("test/") }} | Test suites, factories, mocks |
| {{ src("config/") }} | Phoenix runtime configuration |
| {{ src("priv/") }} | Migrations, static assets, vendored protobuf definitions |
| {{ src("docs/") }} | This documentation |

## Domain code (`lib/logflare/`)

{{ src("lib/logflare/application.ex") }} starts the supervisor tree — see [Supervision Tree](runtime/index.md) for what it owns and in what order.

| Path | Contents | See also |
|---|---|---|
| {{ src("lib/logflare/backends/") }} | Backend adaptors, ingest queue, Broadway pipelines, dynamic scaling | [Backend System](pipelines/index.md), [Broadway Pipelines](pipelines/broadway.md), [Backpressure](pipelines/backpressure.md) |
| {{ src("lib/logflare/backends/adaptor/") }} | Individual adaptor implementations (BigQuery, ClickHouse, Postgres, HTTP-based, S3, Syslog, OTLP) | [Available Adaptors](pipelines/index.md#available-adaptors) |
| {{ src("lib/logflare/backends/ingest_event_queue/") }} | ETS-backed event queue, `BufferCacheWorker`, `QueueJanitor` | [IngestEventQueue](pipelines/broadway.md#ingesteventqueue), [Layer 2](pipelines/backpressure.md#layer-2-queue-buffering-ingesteventqueue) |
| {{ src("lib/logflare/logs/") }} | `LogEvent` struct, OTEL protobuf decoding, ingest transformers | [Log Event Processing](ingestion/log-events.md) |
| {{ src("lib/logflare/endpoints/") }} | Parameterized SQL endpoints, result cache | [Query and Analytics](query/index.md) |
| {{ src("lib/logflare/sql/") }} | SQL parsing and transformation (wraps the `sqlparser_ex` NIF) | [SQL Parsing](query/index.md#sql-parsing-and-transformation) |
| {{ src("lib/logflare/lql/") }} | LQL parser (NimbleParsec) and dialect compilers | [LQL](query/index.md#lql-logflare-query-language) |
| {{ src("lib/logflare/mapper/") }} | Data mapping for ClickHouse ingestion (wraps the `mapper_ex` NIF) | [Rust NIFs](runtime/rust-nifs.md) |
| {{ src("lib/logflare/rules/") }} | Routing rules engine, `RulesTree`, `SourceRouter` | [Routing via Rules](pipelines/index.md#routing-via-rules), [Routing Semantics](pipelines/index.md#routing-semantics) |
| {{ src("lib/logflare/alerting/") }} | Oban-scheduled SQL alerts and notifications | [Alerting](query/alerting.md) |
| {{ src("lib/logflare/context_cache/") }} | Read-through cache with WAL-based invalidation | [Caching](runtime/caching.md), [ContextCache supervisor](runtime/index.md#contextcache-supervisor) |
| {{ src("lib/logflare/networking/") }} | Finch pool definitions | [Networking — Finch pools](runtime/index.md#networking-finch-pools) |
| {{ src("lib/logflare/system_metrics/") }} | Telemetry pollers, `AllLogsLogged` | [System metrics](runtime/index.md#system-metrics) |
| {{ src("lib/logflare/sources/") }} | Source management and source-level workers | — |
| {{ src("lib/logflare/source_schemas/") }} | Source schema storage and reconciliation | — |
| {{ src("lib/logflare/users/") }} | User accounts and API quota helpers | — |
| {{ src("lib/logflare/teams/") }} | Multi-tenant team structure | — |
| {{ src("lib/logflare/billing/") }} | Stripe billing integration | — |
| {{ src("lib/logflare/partners/") }} | Partner integrations (Vercel, etc.) | — |
| {{ src("lib/logflare/auth/") }} | Authentication helpers | — |
| {{ src("lib/logflare/ecto/") }} | Custom Ecto types | — |
| {{ src("lib/logflare/repo/") }} | Repo extensions | — |
| {{ src("lib/logflare/single_tenant.ex") }} | Single-tenant mode flag and helpers | [Deployment Modes](operations/deployment.md) |

## Web layer (`lib/logflare_web/`)

| Path | Contents |
|---|---|
| {{ src("lib/logflare_web/controllers/") }} | HTTP controllers (ingest, query, admin) |
| {{ src("lib/logflare_web/controllers/plugs/") }} | Auth, rate limit, buffer limit, parser plugs |
| {{ src("lib/logflare_web/live/") }} | LiveView dashboard |
| {{ src("lib/logflare_web/components/") }} | UI components |
| {{ src("lib/logflare_web/auth/") }} | Session and API-key authentication |
| {{ src("lib/logflare_web/channels/") }} | Phoenix channels |
| {{ src("lib/logflare_grpc/") }} | gRPC endpoint implementation |

See [Web Layer](operations/web.md) for the pipeline structure and auth model.

## Rust NIFs (`native/`)

| Path | NIF | Purpose |
|---|---|---|
| {{ src("native/sqlparser_ex/") }} | `sqlparser_ex` | SQL parsing |
| {{ src("native/mapper_ex/") }} | `mapper_ex` | Config-driven data mapping for ClickHouse |
| {{ src("native/arrowipc_ex/") }} | `arrowipc_ex` | Arrow IPC serialization for BigQuery |
| {{ src("native/ch_compression_ex/") }} | `ch_compression_ex` | ClickHouse native protocol compression |

See [Rust NIFs](runtime/rust-nifs.md) for call chains and usage.

## Tests (`test/`)

| Path | Contents |
|---|---|
| {{ src("test/support/factory.ex") }} | ExMachina data factories — use `insert/2` and `build/2` |
| {{ src("test/test_helper.exs") }} | Mimic mock setup, test environment bootstrap |
| {{ src("test/logflare/") }} | Domain tests organized by context |
| {{ src("test/logflare_web/") }} | Controller and LiveView tests |
| {{ src("test/logflare_grpc/") }} | gRPC service tests |
| {{ src("test/e2e/") }} | End-to-end Playwright tests |
