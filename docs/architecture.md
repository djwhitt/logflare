# Logflare Architecture

Logflare is a real-time log aggregation and analytics platform built with [Elixir](https://elixir-lang.org/)/[Phoenix](https://www.phoenixframework.org/). It ingests structured log events via HTTP, gRPC, and OpenTelemetry protocols, routes them through configurable pipelines, and stores them in pluggable backend databases. It supports both multi-tenant SaaS and single-tenant deployment modes.

## Table of Contents

- [System Overview](#system-overview)
- [Ingestion Layer](#ingestion-layer)
- [Log Event Processing](#log-event-processing)
- [Backend System](#backend-system)
- [Broadway Pipelines](#broadway-pipelines)
- [Dynamic Pipeline Scaling](#dynamic-pipeline-scaling)
- [Backpressure](#backpressure)
- [Supervision Tree](#supervision-tree)
- [Query and Analytics Layer](#query-and-analytics-layer)
- [Alerting](#alerting)
- [Caching](#caching)
- [Rust NIFs](#rust-nifs)
- [Web Layer](#web-layer)
- [Deployment Modes](#deployment-modes)
- [Key Dependencies](#key-dependencies)

---

## System Overview

```mermaid
flowchart TB
    subgraph Ingestion
        HTTP["HTTP API<br/>(JSON, NDJSON, BERT, Syslog)"]
        GRPC["gRPC"]
        OTLP["OTLP<br/>(Protobuf)"]
    end

    subgraph Processing
        LE["LogEvent Creation"]
        TD["Type Detection<br/>(:log, :metric, :trace)"]
        VT["Validation &<br/>Typecasting"]
    end

    subgraph Routing
        SRC["Source"]
        RULES["Rules Engine"]
    end

    subgraph "Backend Pipelines (Broadway)"
        IEQ["IngestEventQueue<br/>(ETS)"]
        BP["BufferProducer<br/>(GenStage)"]
        BW["Broadway Pipeline"]
    end

    subgraph Backends
        BQ["BigQuery"]
        CH["ClickHouse"]
        PG["PostgreSQL"]
        S3["S3"]
        HTTPB["HTTP Backends<br/>(Datadog, Elastic,<br/>Loki, Webhook, ...)"]
    end

    subgraph Analytics
        EP["Endpoints<br/>(Parameterized SQL)"]
        LQL["LQL<br/>(Query Language)"]
        AL["Alerting<br/>(Oban cron)"]
    end

    HTTP --> LE
    GRPC --> LE
    OTLP --> LE
    LE --> TD --> VT --> SRC
    SRC --> RULES
    RULES --> IEQ
    SRC --> IEQ
    IEQ --> BP --> BW
    BW --> BQ
    BW --> CH
    BW --> PG
    BW --> S3
    BW --> HTTPB

    EP --> BQ
    EP --> CH
    EP --> PG
    AL --> EP
    LQL --> EP
```

---

## Ingestion Layer

Logflare accepts log events through three protocol families, all funneling into the same internal `LogEvent` pipeline.

### HTTP API

The primary ingestion path. The Phoenix router defines an `:api` pipeline with parsers for multiple formats:

- **JSON** / **NDJSON** — standard structured log payloads
- **BERT** — Binary Erlang Term format for Erlang/Elixir clients
- **Syslog** — RFC 5424 syslog messages
- **Protobuf** — OpenTelemetry collector exports (traces, metrics, logs)

Ingestion requests pass through a plug pipeline that handles auth, rate limiting, and buffer limiting:

```mermaid
flowchart LR
    REQ["Request"] --> Auth["VerifyApiAccess"]
    Auth --> Fetch["FetchResource"]
    Fetch --> Access["VerifyResourceAccess"]
    Access --> Plan["SetPlanFromCache"]
    Plan --> Rate["RateLimiter"]
    Rate --> Buffer["BufferLimiter"]
    Buffer --> Controller["Ingest Controller"]
```

Rate limiting is per-source and plan-aware. Buffer limiting prevents queue overflow by rejecting requests when the `IngestEventQueue` is full.

### gRPC

A [gRPC](https://grpc.io/) endpoint runs alongside the HTTP server for high-throughput ingestion from clients that benefit from HTTP/2 streaming and binary serialization.

### OpenTelemetry (OTLP)

Dedicated OTLP endpoints accept [OpenTelemetry](https://opentelemetry.io/) protobuf payloads:

- `ExportTraceServiceRequest` — distributed traces
- `ExportMetricsServiceRequest` — metrics
- `ExportLogsServiceRequest` — logs

These are decoded and converted into `LogEvent` structs via modules in `lib/logflare/logs/` (`otel_log.ex`, `otel_metric.ex`, `otel_trace.ex`).

---

## Log Event Processing

The `Logflare.LogEvent` struct is the core data unit flowing through the system.

### Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | `binary_id` | UUID |
| `body` | `map` | Event payload (user data) |
| `event_type` | `:log \| :metric \| :trace` | Classified type |
| `ingested_at` | `utc_datetime_usec` | Server ingestion time |
| `source_uuid` | `Ecto.UUID` | Immutable source reference |
| `via_rule_id` | `id` | Rule that routed this event |
| `retries` | `integer` | Retry counter for failed inserts |
| `pipeline_error` | `embedded_schema` | Error tracking (stage, type, message) |

### Creation Pipeline

`LogEvent.make/2` runs through these stages for each incoming event:

1. **Mapping** — apply data transformations from source config
2. **Validation** — structural and content validation
3. **Transformation** — field enrichment (copy fields, KV enrichment)
4. **Type Detection** — classify as `:log`, `:metric`, or `:trace`

### Type Detection

`Logflare.Logs.LogEvent.TypeDetection` classifies events using a two-pass strategy:

1. **Explicit metadata** — if `metadata.type` is set (e.g., by OTEL processors), use it directly
2. **Heuristic detection** — inspect body keys:
   - **Trace**: has `trace_id` AND `span_id` AND (`parent_span_id` OR `start_time` OR `duration`)
   - **Metric**: has `metric_type`/`metric` AND `value`/`gauge`/`count`/`sum`
   - **Log**: default fallback

The event type determines routing in backend adaptors (e.g., ClickHouse routes to type-specific OTEL tables).

---

## Backend System

Backends are pluggable storage destinations implemented as adaptors. The `Logflare.Backends.Adaptor` behaviour defines the interface.

### Adaptor Behaviour

**Required callbacks:**

| Callback | Purpose |
|----------|---------|
| `start_link/1` | Start the adaptor process |
| `cast_config/1` | Typecast configuration params |
| `validate_config/1` | Validate config via `Ecto.Changeset` |

**Optional callbacks (query execution):**

| Callback | Purpose |
|----------|---------|
| `execute_query/3` | Run queries against the backend |
| `transform_query/3` | Translate queries between SQL dialects |
| `ecto_to_sql/2` | Convert Ecto queries to backend-native SQL |
| `map_query_parameters/4` | Map parameters across dialects (e.g., BigQuery `@param` to PostgreSQL `$1`) |

**Optional callbacks (ingestion):**

| Callback | Purpose |
|----------|---------|
| `format_batch/1` | Transform batch before sending |
| `pre_ingest/3` | Preprocessing before queueing |
| `consolidated_ingest?/0` | Single pipeline per backend (all sources share batch) |
| `test_connection/1` | Connectivity check |
| `send_alert/3` | Send alert notifications |

### Available Adaptors

| Adaptor | Type | Protocol | Notes |
|---------|------|----------|-------|
| **BigQuery** | Database | gRPC (Storage Write API) | Arrow IPC serialization via Rust NIF |
| **ClickHouse** | Database | Native TCP / HTTP | LZ4 compression via Rust NIF; consolidated ingestion |
| **PostgreSQL** | Database | PostgreSQL wire protocol | Via [Postgrex](https://hexdocs.pm/postgrex/) |
| **Elasticsearch** | Search engine | HTTP | |
| **Datadog** | SaaS | HTTP | |
| **Loki** | Log store | HTTP | [Grafana Loki](https://grafana.com/oss/loki/) push API |
| **S3** | Object storage | HTTP | Byte-based batch splitting |
| **Axiom** | SaaS | HTTP | |
| **Webhook** | HTTP | HTTP | Generic outbound webhook |
| **Slack** | Messaging | HTTP | Slack incoming webhooks |
| **Sentry** | Error tracking | HTTP | |
| **Incident.io** | Incident management | HTTP | |
| **Last9** | Observability | HTTP | |
| **Syslog** | Protocol | TCP/UDP | RFC 5424 |
| **OTLP** | Protocol | HTTP/gRPC | OpenTelemetry export |

HTTP-based adaptors share a common pipeline implementation (`lib/logflare/backends/adaptor/http_based/pipeline.ex`).

### Routing via Rules

The `Logflare.Rules` engine routes log events from a source to additional backends based on configurable criteria. Each rule associates a source with a backend — when an event matches, it's copied to the rule's destination backend.

```mermaid
flowchart LR
    Source["Source"] --> Default["Default Backend"]
    Source --> R1["Rule 1"] --> B1["ClickHouse Backend"]
    Source --> R2["Rule 2"] --> B2["Webhook Backend"]
    Source --> R3["Rule 3"] --> B3["S3 Backend"]
```

---

## Broadway Pipelines

[Broadway](https://hexdocs.pm/broadway/) is the core of the log ingestion pipeline, providing batching, back-pressure, and fault tolerance between the event queue and backend storage.

### Pipeline Implementations

| Pipeline | Adaptor | Batch Size | Processors | Batchers | Pattern |
|----------|---------|-----------|------------|----------|---------|
| `ClickHouseAdaptor.Pipeline` | ClickHouse | 50,000 | 4 | 2 | Consolidated |
| `HttpBased.Pipeline` | Datadog, Elastic, Webhook, etc. | 250 | 3 | 6 | Per-source |
| `PostgresAdaptor.Pipeline` | PostgreSQL | 350 | 5 | 5 | Per-source |
| `S3Adaptor.Pipeline` | S3 | Byte-based | 5 | 1 | Per-source |

### Data Flow Through Broadway

```mermaid
flowchart TB
    subgraph "Event Queue"
        IEQ["IngestEventQueue<br/>(ETS-backed, max 30K/queue)"]
    end

    subgraph "GenStage Producer"
        BP["BufferProducer<br/>(polls on dynamic interval)"]
    end

    subgraph "Broadway Pipeline"
        TX["Transformer<br/>LogEvent → Broadway.Message"]
        PR["Processors<br/>Tag with batcher + batch_key"]
        BA["Batcher<br/>Accumulate by type/key"]
        HB["handle_batch<br/>Bulk insert into backend"]
    end

    subgraph "Acknowledgement"
        ACK{"ack/3"}
        OK["Success:<br/>mark ingested"]
        RETRY["Retriable failure:<br/>requeue with retries++"]
        DROP["Exhausted:<br/>drop from queue"]
    end

    IEQ --> BP --> TX --> PR --> BA --> HB --> ACK
    ACK --> OK
    ACK --> RETRY --> IEQ
    ACK --> DROP
```

### IngestEventQueue

`Logflare.Backends.IngestEventQueue` is a GenServer managing ETS-backed buffers that sit between ingestion and Broadway:

- **ETS mapping table** — fan-out pattern directing events to per-queue tables
- **Per-queue tables** — one per `{source_id, backend_id, pid}` or `{:consolidated, backend_id, pid}`
- **Max queue size** — 30,000 events per queue
- **Event status tracking** — `:pending` | `:ingested`
- **Startup queues** — events land in a queue keyed with `nil` PID until a producer registers, then get moved to the active queue

### BufferProducer

`BufferProducer` is a [GenStage](https://hexdocs.pm/gen_stage/) producer bridging `IngestEventQueue` to Broadway:

- **Dynamic polling interval** — adjusts based on source ingestion metrics (up to 5x slower for low throughput)
- **Two fetch modes:**
  - `pop_pending` — consolidated mode, atomically removes events from queue
  - `take_pending` — standard mode, leaves events in place until acked

### Two Ingestion Patterns

#### Consolidated Ingestion (ClickHouse)

All sources sharing a backend funnel through a **single pipeline**. Events are partitioned by `event_type` (`:log`, `:metric`, `:trace`) via `Broadway.Message.put_batch_key/2`, routing to type-specific OTEL tables.

```mermaid
flowchart LR
    S1["Source A"] --> Q["Queue<br/>{:consolidated, backend_id}"]
    S2["Source B"] --> Q
    S3["Source C"] --> Q
    Q --> P["Shared Pipeline"]
    P -->|"batch_key: :log"| T1["otel_logs table"]
    P -->|"batch_key: :metric"| T2["otel_metrics table"]
    P -->|"batch_key: :trace"| T3["otel_traces table"]
```

Advantages: larger batch sizes (50K), fewer pipelines, better ClickHouse throughput via fewer larger inserts.

#### Per-Source Ingestion (PostgreSQL, HTTP, S3)

Each source-backend pair gets its **own pipeline**, providing source-level isolation.

```mermaid
flowchart LR
    S1["Source A"] --> Q1["Queue<br/>{source_a, backend_id}"] --> P1["Pipeline A"]
    S2["Source B"] --> Q2["Queue<br/>{source_b, backend_id}"] --> P2["Pipeline B"]
    P1 --> DB["Backend"]
    P2 --> DB
```

### Message Lifecycle

A typical Broadway message flows through:

1. **`transform/2`** — wraps `LogEvent` in a `Broadway.Message` with an acknowledger
2. **`handle_message/3`** — tags with batcher (e.g., `:ch`) and batch key (e.g., event type)
3. **`handle_batch/4`** — performs the bulk insert (mapping, serialization, network call)
4. **`ack/3`** — on failure, splits messages into retriable (retries < max → requeue) and exhausted (drop)

---

## Dynamic Pipeline Scaling

`Logflare.Backends.DynamicPipeline` dynamically scales Broadway pipeline **shards** based on queue depth.

```mermaid
flowchart TB
    subgraph "DynamicPipeline (Supervisor)"
        Agent["Agent<br/>(holds state)"]
        Coord["Coordinator<br/>(checks every 5-10s)"]
        subgraph "Pipeline Shards"
            P1["Shard 1"]
            P2["Shard 2"]
            P3["Shard N"]
        end
    end

    IEQ["IngestEventQueue"] -.->|"list_pending_counts"| Coord
    Coord -->|"scale up/down"| P1
    Coord -->|"scale up/down"| P2
    Coord -->|"scale up/down"| P3
```

The `Coordinator` periodically calls a `resolve_count` function that inspects `IngestEventQueue.list_pending_counts/1`. If queue depth exceeds thresholds, shards are added (up to `System.schedulers_online()`). If idle, shards are removed. Rate limiting prevents thrashing.

Currently used by the ClickHouse consolidated pipeline.

---

## Backpressure

Backpressure propagates across multiple layers, from backend storage back to HTTP clients. The system favors graceful degradation — absorbing and buffering aggressively before rejecting inbound requests.

```mermaid
flowchart TB
    subgraph "Layer 1: HTTP Request Rejection"
        RL["RateLimiter Plug<br/>(quota-based)"]
        BL["BufferLimiter Plug<br/>(queue-depth-based)"]
    end

    subgraph "Layer 2: Queue Buffering"
        AQ["Active Queues<br/>(30K cap per queue)"]
        SQ["Startup Queue<br/>(unbounded fallback)"]
    end

    subgraph "Layer 3: QueueJanitor"
        QJ["QueueJanitor<br/>(purges :ingested, drops<br/>pending if queue > max)"]
    end

    subgraph "Layer 4: GenStage / Broadway"
        BP["BufferProducer<br/>(10K internal buffer)"]
        PR["Processors<br/>(demand-driven)"]
        BA["Batchers<br/>(bounded concurrency)"]
    end

    subgraph "Layer 5: Backend Ack"
        BE["Backend Insert"]
        RETRY["Retry (requeue)"]
        DROP["Drop (exhausted)"]
        SILENT["Silent loss<br/>(no-op ack)"]
    end

    RL -->|"pass"| BL
    RL -->|"429"| CLIENT["HTTP Client"]
    BL -->|"pass"| AQ
    BL -->|"429"| CLIENT
    AQ -->|"all full"| SQ
    QJ -.->|"truncate :ingested<br/>drop excess :pending"| AQ
    AQ --> BP --> PR --> BA --> BE
    SQ -->|"producer restart"| AQ
    BE -->|"failure (Syslog)"| RETRY --> AQ
    BE -->|"retries exhausted<br/>(ClickHouse, Syslog)"| DROP
    BE -->|"failure (HTTP, PG, S3)"| SILENT

    style CLIENT fill:#f96
    style DROP fill:#f96
    style SILENT fill:#f96
```

### Layer 1: HTTP Request Rejection

Two plugs in the `:require_ingest_api_auth` pipeline gate requests before any queuing occurs:

**RateLimiter** (`plugs/rate_limiter.ex`) — checks user-level and per-source API quotas derived from the billing plan via `Users.API.verify_api_rates_quotas/1`. Returns **HTTP 429** with `X-Rate-Limit` headers when quotas are exceeded. This is purely rate-based and independent of backend health.

**BufferLimiter** (`plugs/buffer_limiter.ex`) — calls `Backends.cached_local_pending_buffer_full?/1`, which reads cached queue depths from `PubSubRates.Cache`. Returns **HTTP 429 "Buffer Full"** when **all** queues for the source's backends exceed 30,000 events (strict `>`, so exactly 30,000 is not considered full). This is the mechanism by which downstream congestion surfaces to clients.

The buffer fullness check uses **total queue size** (both `:pending` and `:ingested` events), not just pending count. This means uncleaned `:ingested` events (from non-consolidated pipelines with no-op ack callbacks) contribute to the fullness threshold.

**Limitation: consolidated backends are not checked.** `BufferCacheWorker` caches consolidated queue stats under the key `{:consolidated, backend_id, "buffers"}`, but `buffer_full_for_backend?/2` queries with `{source_id, backend_id, "buffers"}` — a different key. The BufferLimiter therefore never sees consolidated queue depths (currently only ClickHouse). If the system default backend (queued at `{source_id, nil}`) is draining normally but the consolidated ClickHouse queue is overflowing, no 429 is returned.

### Layer 2: Queue Buffering (IngestEventQueue)

Once past the HTTP plugs, events enter `IngestEventQueue.add_to_table/3`. This layer **never rejects and never drops** — it always returns `:ok`. Instead, it applies smart distribution:

- Events are distributed round-robin across available per-producer **active queues**
- Queues at or above 30,000 events (`@max_queue_size`) are **skipped** — events are redirected to less-full queues
- If **all** active queues are full, events fall back to the **startup queue** (keyed with `nil` pid)
- No backpressure signal is sent upstream

**The startup queue is unbounded.** It has no size check on insertion. It is only drained when a `BufferProducer` starts (or restarts) and calls `IngestEventQueue.move/2` to transfer events to its active queue. If a producer is already running and healthy, nothing reads from the startup queue. In sustained overload where all active queues are full, the startup queue grows without limit.

For the standard (non-consolidated) path, two types of queues exist per `{source_id, backend_id}`:

| Queue Type | Key | Drained By | Size Limited? |
|-----------|-----|-----------|---------------|
| Active | `{source_id, backend_id, pid}` | `BufferProducer` polling | Yes (30K soft cap via `add_to_table` routing) |
| Startup | `{source_id, backend_id, nil}` | `BufferProducer` init (`move/2`) | No |

For the consolidated path (ClickHouse), the same pattern applies with `{:consolidated, backend_id, pid/nil}` keys.

### Layer 3: QueueJanitor

`IngestEventQueue.QueueJanitor` is a per-source-backend GenServer that performs periodic cleanup. It is started by `AdaptorSupervisor` for **non-consolidated pipelines only** — consolidated backends (ClickHouse) do not run a QueueJanitor.

**Two cleanup actions per queue:**

1. **Truncate `:ingested` events** — removes events that were fetched by `BufferProducer` (marked `:ingested` via `mark_ingested/2`) but whose ack callback did nothing. When source throughput is > 100 avg, all `:ingested` events are truncated; otherwise, a remainder of 100 is kept.

2. **Drop excess `:pending` events** — if total queue size exceeds `max` (default: `30,000 * 1.2 = 36,000`), drops 5% of `:pending` events and logs a warning. This is the hard safety valve against runaway queue growth.

**Startup queues are excluded** from the drop check (`pid != nil` guard at line 98), so the startup queue can grow past the max threshold without triggering drops.

The janitor interval scales with throughput: every 1s at high load (avg >= 2000), up to every 10s at low load (avg < 100).

| Config | Standard | Consolidated (if it ran) |
|--------|----------|------------------------|
| Max queue size | 36,000 | 360,000 (10x multiplier) |
| Purge ratio | 5% of `:pending` | 5% of `:pending` |
| Interval | 1–10s (adaptive) | 1–10s (adaptive) |

### Layer 4: GenStage Demand and Broadway Throttling

**BufferProducer** is a [GenStage](https://hexdocs.pm/gen_stage/) producer with an internal buffer of 10,000 events (configurable via `buffer_size` option). It only fetches from `IngestEventQueue` when downstream Broadway processors signal demand.

**Fetch modes differ by pipeline type:**

| Mode | Used By | Fetch | Cleanup |
|------|---------|-------|---------|
| Consolidated | ClickHouse | `pop_pending/2` — atomically removes events from ETS | Events gone immediately; ack handles failures |
| Per-source | HTTP, Postgres, S3, Syslog | `take_pending/2` + `mark_ingested/2` — leaves events in ETS as `:ingested` | QueueJanitor truncates `:ingested` events |

When demand stops (downstream saturated):
- The producer stops polling the queue
- If the internal 10K buffer fills before demand resumes, GenStage discards events via `format_discarded/2` (logged as a warning, throttled to once per 5 seconds)
- **This is the first point where events are silently lost** without client awareness

**Polling interval** scales with source throughput for non-consolidated producers (1s at high load, up to 5s at low load). Consolidated producers use a fixed interval.

Broadway pipelines apply further throttling through their configuration:

| Pipeline | Processor Concurrency | min_demand | Batch Size | Batch Timeout | Batcher Concurrency |
|----------|----------------------|------------|------------|---------------|-------------------|
| ClickHouse | 4 | 1 | 50,000 | 4s | 2 |
| HTTP-based | 3 | 1 | 250 | — | 6 |
| PostgreSQL | 5 | 1 | 350 | — | 5 |
| S3 | 5 | — | 10,000 (or 8MB) | configurable | 1 |

Low `min_demand` values mean processors pull conservatively from the producer, letting batchers accumulate events. Batcher concurrency caps how many backend writes happen in parallel. When all slots are busy, demand to the producer drops to zero, stalling the pipeline until capacity frees up.

### Layer 5: Backend Acknowledgment and Failure Handling

After Broadway processes a batch, the acknowledger determines what happens to events. Behavior varies significantly by adaptor:

**ClickHouse** (`@max_retries = 0`):
- Events were already removed from the queue by `pop_pending`
- On success: nothing to clean up — events are already gone
- On failure: **all failed events are dropped immediately** (logged as warning). Since `@max_retries = 0`, every failure is treated as exhaustion. Events are deleted from the queue (no-op since already popped) and permanently lost
- The `NativeIngester` layer below the pipeline has its own retry logic (1 retry with 500ms delay for connection/timeout errors), but pipeline-level ack sees only the final result

**Syslog** (`@max_retries = 1`):
- On failure (first attempt): events are deleted from queue and re-added as fresh `:pending` entries with `retries` incremented. This gives them one more chance through the pipeline
- On failure (second attempt): events are deleted and permanently dropped (logged as warning)

**HTTP-based, PostgreSQL, S3** (no-op ack):
- The `ack/3` callback is a no-op (`# TODO: re-queue failed`)
- On success: events remain in ETS with `:ingested` status. `QueueJanitor` eventually truncates them
- On failure: **events are silently lost**. They were marked `:ingested` before processing (in `BufferProducer.do_fetch/2`), the no-op ack doesn't revert them, and `QueueJanitor` cleans them up as if they succeeded. No retry occurs, no error is logged at the ack layer

| Adaptor | Failure Handling | Data Loss on Failure? |
|---------|-----------------|----------------------|
| ClickHouse | Explicit drop, logged | Yes (immediate, logged) |
| Syslog | 1 retry, then drop | Yes (after 1 retry, logged) |
| HTTP-based | No-op ack | Yes (silent, cleaned by QueueJanitor) |
| PostgreSQL | No-op ack | Yes (silent, cleaned by QueueJanitor) |
| S3 | No-op ack | Yes (silent, cleaned by QueueJanitor) |

### Pressure Cascade

When a backend slows down or becomes unavailable, pressure propagates upward through different paths depending on the pipeline type.

**Non-consolidated backends (HTTP, Postgres, S3, Syslog):**

1. Backend inserts slow → Broadway batcher/processor slots saturate
2. Broadway demand drops → BufferProducer stops polling IngestEventQueue
3. Active queue depths grow toward 30K (both `:pending` and uncleaned `:ingested` events count)
4. `BufferCacheWorker` (every 2.5s) caches queue depths → `PubSubRates.Cache`
5. BufferLimiter plug starts returning **429 Buffer Full**
6. QueueJanitor (every 1–10s) drops 5% of `:pending` if queue exceeds 36K

**Consolidated backends (ClickHouse):**

1. ClickHouse inserts slow → Broadway batcher/processor slots saturate
2. Broadway demand drops → BufferProducer stops polling
3. Active queue depths grow toward 30K per shard
4. **`DynamicPipeline` scales up** — Coordinator checks `list_pending_counts` every 10s, adds shards when any queue exceeds 5,000 (up to `System.schedulers_online()`)
5. If all shards at max and all active queues full → new events overflow to **startup queue** (unbounded)
6. **BufferLimiter does not trigger** for consolidated queues (cache key mismatch)
7. The only HTTP-level protection is `RateLimiter` (quota-based, independent of queue depth)

### Key Thresholds

| Constant | Value | Location | Purpose |
|----------|-------|----------|---------|
| `@max_queue_size` | 30,000 | `ingest_event_queue.ex:17` | Per-queue routing cap in `add_to_table` |
| `@max_pending_buffer_len_per_queue` | 30,000 | `backends.ex:38` | BufferLimiter fullness threshold |
| QueueJanitor `max` | 36,000 | `queue_janitor.ex:24` | Hard drop threshold (30K * 1.2) |
| QueueJanitor consolidated `max` | 360,000 | `queue_janitor.ex:44` | 10x multiplier (not currently used) |
| `@scaling_threshold` | 5,000 | `clickhouse_adaptor.ex:36` | DynamicPipeline scale-up trigger |
| GenStage `buffer_size` | 10,000 | `buffer_producer.ex:49` | Internal producer buffer before discard |
| `BufferCacheWorker` interval | 2,500ms | `buffer_cache_worker.ex:13` | How often queue depths are cached |
| `QueueJanitor` interval | 1,000–10,000ms | `queue_janitor.ex:21` | Adaptive cleanup frequency |

### Design Trade-offs and Known Gaps

- **No end-to-end acknowledgment** — once a client receives HTTP 200, the event may still be lost at GenStage overflow, backend exhaustion, or via no-op ack cleanup. Clients are not notified of post-acceptance data loss.
- **Consolidated queues bypass BufferLimiter** — the `BufferCacheWorker` caches consolidated queue stats under `{:consolidated, backend_id}` keys, but `buffer_full_for_backend?` queries with `{source_id, backend_id}` keys. This means ClickHouse queue overflow cannot trigger HTTP 429 responses. Only the rate-based `RateLimiter` provides HTTP-level protection for consolidated backends.
- **Startup queue is unbounded** — no component enforces a size limit on the startup queue. `QueueJanitor` explicitly skips it (`pid != nil` guard). In sustained overload where all active queues are full, the startup queue grows without limit, posing a memory exhaustion risk.
- **No QueueJanitor for consolidated backends** — the janitor is only started by `AdaptorSupervisor` (per-source pipelines). ClickHouse relies on `pop_pending` (atomic removal) for cleanup, but has no safety valve for excess `:pending` events if the pipeline can't keep up.
- **Silent data loss on failure (HTTP, Postgres, S3)** — the no-op ack callbacks mean failed events are treated identically to successful ones. `QueueJanitor` cleans them up as `:ingested` without logging the failure.
- **Local-node buffer checks** — `BufferLimiter` inspects only the local node's queue depths. In a cluster, total capacity before rejection is `30K x nodes x queues_per_node` for non-consolidated backends.
- **No circuit breaker** — the system has no mechanism to stop sending to a consistently failing backend. ClickHouse events are dropped on every failure; HTTP/Postgres events are silently lost. There is no exponential backoff, failure threshold, or open/half-open/closed state machine.

---

## Supervision Tree

```mermaid
flowchart TB
    App["Logflare.Application"]

    subgraph "Core Infrastructure"
        Repo["Repo"]
        Vault["Vault"]
        PubSub["Phoenix.PubSub"]
        Oban["Oban"]
        Cache["ContextCache.Supervisor"]
    end

    subgraph "Metrics & Tracking"
        Counters["Counters (ETS)"]
        Rate["RateCounters (ETS)"]
        PSR["PubSubRates"]
        SysMet["SystemMetricsSup"]
        AUT["ActiveUserTracker"]
    end

    subgraph "Backend Supervisor"
        IEQ["IngestEventQueue"]

        subgraph "ConsolidatedSup"
            DS1["DynamicSupervisor"]
            CSW["ConsolidatedSupWorker"]
            DP["DynamicPipeline<br/>(per backend)"]
            DS1 --> DP
        end

        subgraph "PartitionSupervisor (SourcesSup)"
            SS1["SourceSup (Source A)"]
            SS2["SourceSup (Source B)"]
            SSN["SourceSup (Source N)"]
        end
    end

    subgraph "SourceSup Detail"
        RCS["RateCounterServer"]
        RIC["RecentInsertsCacher"]
        ENS["EmailNotificationServer"]
        SSW["SourceSupWorker"]
        AS["AdaptorSupervisor"]
        QJ["QueueJanitor"]
        Pipeline["Pipeline (Broadway)"]
        AS --> QJ
        AS --> Pipeline
    end

    subgraph "Web"
        Endpoint["Phoenix Endpoint"]
        GRPC["gRPC Server"]
    end

    App --> Repo
    App --> Vault
    App --> PubSub
    App --> Oban
    App --> Cache
    App --> Counters
    App --> Rate
    App --> PSR
    App --> IEQ
    App --> ConsolidatedSup
    App --> PartitionSupervisor
    App --> Endpoint
    App --> GRPC
    App --> SysMet
    App --> AUT

    SS1 --> RCS
    SS1 --> RIC
    SS1 --> ENS
    SS1 --> SSW
    SS1 --> AS
```

Key ordering constraints:
- **Repo + Vault** must start before anything touching the database
- **Backends** must start before `Source.Supervisor` (backends register queues that sources write to)
- **Counters** must start before `Source.Supervisor` (sources call counters during init)

---

## Query and Analytics Layer

### Endpoints

`Logflare.Endpoints` provides parameterized SQL query endpoints for analytics. Each endpoint defines a SQL query template with named parameters that can be executed on demand.

**Query execution pipeline:**

```mermaid
flowchart LR
    REQ["API Request<br/>+ parameters"] --> EXP["Expand<br/>subqueries"]
    EXP --> TX["Sql.transform<br/>(rewrite sources → tables)"]
    TX --> DT["Dialect<br/>translation"]
    DT --> PM["Parameter<br/>mapping"]
    PM --> EXEC["adaptor.execute_query"]
    EXEC --> RED["PII<br/>redaction"]
    RED --> RES["Response"]
```

Endpoints support:
- **Three SQL dialects:** BigQuery SQL, ClickHouse SQL, PostgreSQL SQL
- **Subquery expansion** — references to other endpoints or alerts are inlined as CTEs
- **Sandboxed queries** — endpoints can accept runtime LQL/SQL parameters, constrained to declared CTEs
- **Result caching** — configurable TTL via `ResultsCache`
- **Labels** — extracted from config, headers, and query params for downstream filtering

### LQL (Logflare Query Language)

LQL is a backend-agnostic query DSL parsed via [NimbleParsec](https://hexdocs.pm/nimble_parsec/). It compiles to dialect-specific SQL for each backend.

| LQL Dialect | Target Backend |
|-------------|---------------|
| `:bigquery` | BigQuery SQL |
| `:clickhouse` | ClickHouse SQL |
| `:postgres` | PostgreSQL SQL |

Core operations:
- `decode/2` — parse LQL string into rule structs (`FilterRule`, `SelectRule`, `FromRule`)
- `encode/1` — serialize rules back to LQL string
- `apply_rules/3` — apply rules to an `Ecto.Query`
- `to_sandboxed_sql/3` — compile to SQL for sandboxed endpoint execution

### SQL Parsing and Transformation

SQL parsing is handled by a Rust NIF (`sqlparser_ex`) wrapping the [`sqlparser`](https://crates.io/crates/sqlparser) crate. The Elixir interface in `Logflare.Sql` provides:

- **`transform/3`** — rewrite source names to physical table names, apply schema prefixes
- **`expand_subqueries/2`** — inline endpoint/alert references as CTEs
- **Dialect translation** — convert between BigQuery, ClickHouse, and PostgreSQL SQL variants

---

## Alerting

The alerting system executes SQL queries on a cron schedule and sends notifications when results are non-empty.

```mermaid
flowchart TB
    CRON["Oban Cron<br/>(AlertSchedulerWorker)"] -->|"schedule"| JOBS["AlertWorker Jobs"]
    JOBS -->|"execute"| QUERY["SQL Query<br/>(via Endpoints pipeline)"]
    QUERY -->|"results?"| CHECK{"Non-empty?"}
    CHECK -->|"yes"| NOTIFY["Notifications"]
    CHECK -->|"no"| DONE["Done"]
    NOTIFY --> WH["Webhook"]
    NOTIFY --> SL["Slack"]
    NOTIFY --> BA["Backend-specific<br/>(adaptor.send_alert/3)"]
```

Alerts are managed via [Oban](https://hexdocs.pm/oban/) job queues:
- `schedule_alert/1` parses the cron expression, generates the next 5 run dates, and inserts Oban jobs
- `trigger_alert_now/1` allows immediate manual execution
- Execution history (last 50 runs) and future jobs are queryable

---

## Caching

`Logflare.ContextCache` is a read-through caching layer built on [Cachex](https://hexdocs.pm/cachex/) that reduces database load for hot paths.

**Design:**
- One cache per context module (e.g., `Logflare.Users.Cache`, `Logflare.Sources.Cache`)
- Results wrapped in `{:cached, value}` tuples to distinguish cached `nil` from cache miss
- Cache busting via WAL-based invalidation — matches on struct `:id` fields across three patterns (single structs, lists of structs, `{:ok, struct}` tuples)
- Optional `bust_by/1` callback for custom invalidation keys

---

## Rust NIFs

Four Rust [NIFs](https://www.erlang.org/doc/tutorial/nif.html) (Native Implemented Functions) built with [Rustler](https://github.com/rusterlium/rustler) offload CPU-intensive operations to avoid blocking the BEAM scheduler.

| NIF | Crate/Library | Purpose | Used By |
|-----|--------------|---------|---------|
| `sqlparser_ex` | [`sqlparser`](https://crates.io/crates/sqlparser) | SQL parsing and AST manipulation | `Logflare.Sql.Parser` — query transformation, validation, dialect translation |
| `mapper_ex` | Custom | Config-driven data mapping | `Logflare.Mapper` — transforms log event bodies before ClickHouse insertion; config compiled once, reused per-event |
| `arrowipc_ex` | [`arrow`](https://crates.io/crates/arrow) | Arrow IPC serialization | `BigQueryAdaptor.ArrowIPC` — serializes dataframes for BigQuery [Storage Write API](https://cloud.google.com/bigquery/docs/write-api) (8MB chunk splitting) |
| `ch_compression_ex` | [`lz4`](https://crates.io/crates/lz4), [`cityhash-rs`](https://crates.io/crates/cityhash-rs) | LZ4 compression + CityHash checksums | `ClickHouseAdaptor.NativeIngester.Compression` — ClickHouse [native protocol](https://clickhouse.com/docs/en/native-protocol/basics) compression envelope |

### Call Chains

**SQL Parsing:**
```
Logflare.Sql.Parser.Native (NIF) → Logflare.Sql.Parser → Logflare.Sql
  → Endpoints, Alerting, Rules validation, Dialect translation
```

**Data Mapping (ClickHouse only):**
```
Logflare.Mapper.Native (NIF) → Logflare.Mapper
  → MappingConfigStore (compile once, cache) → ClickHouse Pipeline (map per-event)
```

**Arrow Serialization (BigQuery only):**
```
ArrowIPC Native (NIF) → BigQueryAdaptor.ArrowIPC → GoogleApiClient.append_rows
  → gRPC → BigQuery Storage Write API
```

**ClickHouse Compression:**
```
ChCompression (NIF) → Compression → Connection → NativeIngester
  → ClickHouseAdaptor (native TCP inserts)
```

---

## Web Layer

The web layer uses [Phoenix](https://www.phoenixframework.org/) with [LiveView](https://hexdocs.pm/phoenix_live_view/) for real-time UI and a REST API documented with [OpenApiSpex](https://hexdocs.pm/open_api_spex/).

### Pipelines

| Pipeline | Purpose | Auth |
|----------|---------|------|
| `:browser` | Dashboard UI (LiveView) | Session-based, team/plan context |
| `:api` | REST API (JSON/BERT) | API key via `VerifyApiAccess` |
| `:otlp_api` | OTLP ingestion (Protobuf) | API key |
| `:require_ingest_api_auth` | Log ingestion | API key + rate limiting + buffer limiting |
| `:require_mgmt_api_auth` | Management API | Private-scoped API key |
| `:partner_api` | Partner integrations | Partner-scoped API key |

### OAuth2

Logflare acts as an OAuth2 provider (via [PhoenixOauth2Provider](https://hexdocs.pm/phoenix_oauth2_provider/)) for integrations with Vercel and Cloudflare.

### Real-Time Features

- **LiveView dashboard** — real-time log tailing, source management, endpoint testing
- **PubSub rates** — ingestion rates broadcast via [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/) for live UI updates
- **Active user tracking** — presence tracking for connected dashboard users

---

## Deployment Modes

### Multi-Tenant (SaaS)

Full-featured mode with:
- User/team management and billing ([Stripe](https://stripe.com/docs/api) integration)
- Feature flags via [ConfigCat](https://configcat.com/docs/)
- Cluster discovery via [libcluster](https://hexdocs.pm/libcluster/)
- Google Cloud service accounts for BigQuery (via [Goth](https://hexdocs.pm/goth/))
- Partner integrations (Vercel)

### Single-Tenant

Simplified deployment with:
- Auto-seeded default user and plan
- Optional **Supabase mode** — creates predefined sources and endpoints for Supabase log routing
- Optional PostgreSQL-only backend (no BigQuery dependency)
- Controlled via `Logflare.SingleTenant.single_tenant?/0`

---

## Key Dependencies

### Core Framework

| Dependency | Version | Purpose | Docs |
|-----------|---------|---------|------|
| Phoenix | ~> 1.7 | Web framework | [hexdocs.pm/phoenix](https://hexdocs.pm/phoenix/) |
| Phoenix LiveView | ~> 1.0 | Real-time UI | [hexdocs.pm/phoenix_live_view](https://hexdocs.pm/phoenix_live_view/) |
| Bandit | ~> 1.8 | HTTP server | [hexdocs.pm/bandit](https://hexdocs.pm/bandit/) |
| Ecto | ~> 3.13 | Database layer | [hexdocs.pm/ecto](https://hexdocs.pm/ecto/) |

### Data Processing

| Dependency | Version | Purpose | Docs |
|-----------|---------|---------|------|
| Broadway | (fork) | Stream processing pipelines | [hexdocs.pm/broadway](https://hexdocs.pm/broadway/) |
| GenStage | — | Producer-consumer pipelines | [hexdocs.pm/gen_stage](https://hexdocs.pm/gen_stage/) |
| Oban | ~> 2.19 | Background job queue | [hexdocs.pm/oban](https://hexdocs.pm/oban/) |
| NimbleParsec | ~> 1.4 | Parser combinators (LQL) | [hexdocs.pm/nimble_parsec](https://hexdocs.pm/nimble_parsec/) |

### Backend Drivers

| Dependency | Purpose | Docs |
|-----------|---------|------|
| google_api_big_query | BigQuery client | [hexdocs.pm/google_api_big_query](https://hexdocs.pm/google_api_big_query/) |
| Ch | ClickHouse driver | [hexdocs.pm/ch](https://hexdocs.pm/ch/) |
| Postgrex | PostgreSQL driver | [hexdocs.pm/postgrex](https://hexdocs.pm/postgrex/) |

### Caching & Infrastructure

| Dependency | Purpose | Docs |
|-----------|---------|------|
| Cachex | ~> 4.0 | In-memory caching | [hexdocs.pm/cachex](https://hexdocs.pm/cachex/) |
| libcluster | ~> 3.2 | Cluster formation | [hexdocs.pm/libcluster](https://hexdocs.pm/libcluster/) |
| Syn | (fork) | Process registry | [hexdocs.pm/syn](https://hexdocs.pm/syn/) |

### Observability

| Dependency | Purpose | Docs |
|-----------|---------|------|
| OpenTelemetry | ~> 1.3 | Distributed tracing | [hexdocs.pm/opentelemetry](https://hexdocs.pm/opentelemetry/) |
| Telemetry | ~> 1.0 | Metrics instrumentation | [hexdocs.pm/telemetry](https://hexdocs.pm/telemetry/) |
| Mimic | ~> 2.0 | Test mocking | [hexdocs.pm/mimic](https://hexdocs.pm/mimic/) |
| ExMachina | ~> 2.3 | Test factories | [hexdocs.pm/ex_machina](https://hexdocs.pm/ex_machina/) |

### Rust NIFs

| Dependency | Crate | Docs |
|-----------|-------|------|
| Rustler | — | [hexdocs.pm/rustler](https://hexdocs.pm/rustler/) |
| sqlparser | — | [docs.rs/sqlparser](https://docs.rs/sqlparser/) |
| arrow | — | [docs.rs/arrow](https://docs.rs/arrow/) |
