# Rust NIFs

Four Rust [NIFs](https://www.erlang.org/doc/tutorial/nif.html) (Native Implemented Functions) built with [Rustler](https://github.com/rusterlium/rustler) offload CPU-intensive operations to avoid blocking the BEAM scheduler.

| NIF | Crate/Library | Purpose | Used By |
|-----|--------------|---------|---------|
| `sqlparser_ex` | [`sqlparser`](https://crates.io/crates/sqlparser) | SQL parsing and AST manipulation | {{ mod("Logflare.Sql.Parser") }} — query transformation, validation, dialect translation |
| `mapper_ex` | Custom | Config-driven data mapping | {{ mod("Logflare.Mapper") }} — transforms log event bodies before ClickHouse insertion; config compiled once, reused per-event |
| `arrowipc_ex` | [`arrow`](https://crates.io/crates/arrow) | Arrow IPC serialization | `BigQueryAdaptor.ArrowIPC` — serializes dataframes for BigQuery [Storage Write API](https://cloud.google.com/bigquery/docs/write-api) (8MB chunk splitting) |
| `ch_compression_ex` | [`lz4`](https://crates.io/crates/lz4), [`cityhash-rs`](https://crates.io/crates/cityhash-rs) | LZ4 compression + CityHash checksums | `ClickHouseAdaptor.NativeIngester.Compression` — ClickHouse [native protocol](https://clickhouse.com/docs/en/native-protocol/basics) compression envelope |

## Call Chains

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
