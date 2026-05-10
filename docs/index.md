# Logflare Architecture

Logflare is a real-time log aggregation and analytics platform built with [Elixir](https://elixir-lang.org/)/[Phoenix](https://www.phoenixframework.org/). It ingests structured log events via HTTP, gRPC, and OpenTelemetry protocols, routes them through configurable pipelines, and stores them in pluggable backend databases. It supports both multi-tenant SaaS and single-tenant deployment modes.

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

## How to read these docs

- **[Ingestion](ingestion/index.md)** — how events arrive over HTTP, gRPC, and OTLP, and how the `LogEvent` struct is constructed and classified.
- **[Pipelines](pipelines/index.md)** — backend adaptors, Broadway pipelines, dynamic scaling, and the multi-layer backpressure model.
- **[Runtime](runtime/index.md)** — supervision tree, caching, and Rust NIFs.
- **[Query](query/index.md)** — endpoints, LQL, SQL parsing, and the alerting system.
- **[Operations](operations/index.md)** — web layer, deployment modes, and key dependencies.
