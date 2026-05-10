# Key Dependencies

## Core Framework

| Dependency | Version | Purpose | Docs |
|-----------|---------|---------|------|
| Phoenix | ~> 1.7 | Web framework | [hexdocs.pm/phoenix](https://hexdocs.pm/phoenix/) |
| Phoenix LiveView | ~> 1.0 | Real-time UI | [hexdocs.pm/phoenix_live_view](https://hexdocs.pm/phoenix_live_view/) |
| Bandit | ~> 1.8 | HTTP server | [hexdocs.pm/bandit](https://hexdocs.pm/bandit/) |
| Ecto | ~> 3.13 | Database layer | [hexdocs.pm/ecto](https://hexdocs.pm/ecto/) |

## Data Processing

| Dependency | Version | Purpose | Docs |
|-----------|---------|---------|------|
| Broadway | (fork) | Stream processing pipelines | [hexdocs.pm/broadway](https://hexdocs.pm/broadway/) |
| GenStage | — | Producer-consumer pipelines | [hexdocs.pm/gen_stage](https://hexdocs.pm/gen_stage/) |
| Oban | ~> 2.19 | Background job queue | [hexdocs.pm/oban](https://hexdocs.pm/oban/) |
| NimbleParsec | ~> 1.4 | Parser combinators (LQL) | [hexdocs.pm/nimble_parsec](https://hexdocs.pm/nimble_parsec/) |

## Backend Drivers

| Dependency | Purpose | Docs |
|-----------|---------|------|
| google_api_big_query | BigQuery client | [hexdocs.pm/google_api_big_query](https://hexdocs.pm/google_api_big_query/) |
| Ch | ClickHouse driver | [hexdocs.pm/ch](https://hexdocs.pm/ch/) |
| Postgrex | PostgreSQL driver | [hexdocs.pm/postgrex](https://hexdocs.pm/postgrex/) |

## Caching & Infrastructure

| Dependency | Purpose | Docs |
|-----------|---------|------|
| Cachex | ~> 4.0 | In-memory caching | [hexdocs.pm/cachex](https://hexdocs.pm/cachex/) |
| libcluster | ~> 3.2 | Cluster formation | [hexdocs.pm/libcluster](https://hexdocs.pm/libcluster/) |
| Syn | (fork) | Process registry | [hexdocs.pm/syn](https://hexdocs.pm/syn/) |

## Observability

| Dependency | Purpose | Docs |
|-----------|---------|------|
| OpenTelemetry | ~> 1.3 | Distributed tracing | [hexdocs.pm/opentelemetry](https://hexdocs.pm/opentelemetry/) |
| Telemetry | ~> 1.0 | Metrics instrumentation | [hexdocs.pm/telemetry](https://hexdocs.pm/telemetry/) |
| Mimic | ~> 2.0 | Test mocking | [hexdocs.pm/mimic](https://hexdocs.pm/mimic/) |
| ExMachina | ~> 2.3 | Test factories | [hexdocs.pm/ex_machina](https://hexdocs.pm/ex_machina/) |

## Rust NIFs

| Dependency | Crate | Docs |
|-----------|-------|------|
| Rustler | — | [hexdocs.pm/rustler](https://hexdocs.pm/rustler/) |
| sqlparser | — | [docs.rs/sqlparser](https://docs.rs/sqlparser/) |
| arrow | — | [docs.rs/arrow](https://docs.rs/arrow/) |
