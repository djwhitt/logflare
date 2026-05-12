# Optimization Targets

A running list of optimization opportunities in the codebase, weighted toward the ingest hot path. Item references are exact at the time of writing — verify line numbers before opening a PR.

This page is hand-maintained. Add or retire items as work lands; preserve the priority ordering when shuffling.

## Scoring

Items are scored `1–5` (higher is better) on three axes, then weighted into a single priority:

- **Ease** — small/local (`5`) vs. broad/invasive (`1`)
- **Safety** — low risk (`5`) vs. high risk (`1`); inverse of implementation risk
- **Impact** — expected production effect at tens of millions of events/day
- **Priority** — `Impact × 0.5 + Ease × 0.3 + Safety × 0.2`

When scores are close, prefer **Quick win** items over **Strategic** ones unless profiling clearly points at the strategic path.

## Priority Table

| # | Lane | Target | Ease | Safety | Impact | Score |
|---|------|--------|---:|---:|---:|---:|
| 1 | Quick win | Rewrite `MetadataCleaner.flatten/1` to avoid intermediate lists | 4 | 4 | 5 | 4.50 |
| 2 | Quick win | Fix `list_counts_with_tids/1` queue-stats fast path | 4 | 4 | 4 | 4.00 |
| 3 | Quick win | No-op short-circuit in `update_all_keys_deep/2` (paired with #5) | 3 | 3 | 5 | 4.00 |
| 4 | Quick win | Reduce BigQuery resolver source-metrics duplication | 3 | 4 | 4 | 3.70 |
| 5 | Quick win | BigQuery key sanitizer fast path | 3 | 3 | 4 | 3.50 |
| 6 | Quick win | Default-case fast path for `apply_custom_event_message/2` | 3 | 3 | 4 | 3.50 |
| 7 | Quick win | Use batch-level timestamps in `LogEvent.make/2` | 4 | 4 | 3 | 3.50 |
| 8 | Quick win | Count pending events directly from known queue tids | 4 | 4 | 3 | 3.50 |
| 9 | Measured | Pop non-default backend queues instead of mark-ingested + janitor | 3 | 3 | 4 | 3.50 |
| 10 | Strategic | Batch source-rule routing instead of recursive single-event ingest | 2 | 2 | 5 | 3.50 |
| 11 | Strategic | Replace Ecto changeset construction in `LogEvent.make/2` | 2 | 2 | 5 | 3.50 |
| 12 | Quick win | Remove duplicate `ensure_source_sup_started/1` call | 5 | 4 | 2 | 3.30 |
| 13 | Measured | Benchmark ETS mapper-table `read_concurrency` | 4 | 3 | 3 | 3.30 |
| 14 | Quick win | Count valid events once and pass count through dispatch | 4 | 5 | 2 | 3.20 |
| 15 | Measured | Aggregate buffer lengths in one `BufferCacheWorker` pass | 3 | 4 | 3 | 3.20 |
| 16 | Quick win | Cache default-ingest backend ids for buffer-full checks | 4 | 4 | 2 | 3.00 |
| 17 | Measured | Preparse drop-filter paths and regexes | 3 | 3 | 3 | 3.00 |
| 18 | Strategic | Deduplicate backend-rule dispatch if semantics allow | 2 | 2 | 4 | 3.00 |
| 19 | Opportunistic | Simplify resolver count math | 5 | 5 | 1 | 3.00 |
| 20 | Opportunistic | Rework `fetch_events/2` flattening / nested-list accumulation | 4 | 4 | 2 | 2.80 |
| 21 | Opportunistic | Fix BigQuery IAM paginator accumulation | 5 | 4 | 1 | 2.80 |
| 22 | Evidence needed | Optimize ClickHouse `Array(JSON)` encoding (only with profiling) | 2 | 2 | 3 | 2.50 |
| 23 | Opportunistic | Avoid dynamic atoms for Goth partition supervisor names | 3 | 4 | 1 | 2.20 |
| 24 | Dev only | Defer eager `Mimic.copy` at test boot | 2 | 2 | 1 | 1.50 |
| 25 | Maintenance | Split `dialect_translation.ex` | 1 | 2 | 1 | 1.20 |

## Tier 1: High-Value Quick Wins

### 1. Rewrite `MetadataCleaner.flatten/1` to avoid intermediate lists
**Where:** {{ src("lib/logflare/logs/cleaner.ex", 50) }}, {{ src("lib/logflare/logs/log_event.ex", 98) }} · **Score:** E4 / S4 / I5 — **4.50**

Runs for every valid ingest event. Currently builds nested lists via `Enum.flat_map/2`, uses `Enum.with_index/1`, then converts to a map with `Map.new/1`. Rewrite to produce the final map directly via a tail-recursive walker, preserving list-index keys, empty-container behavior, and collision semantics.

### 2. Fix `list_counts_with_tids/1` queue-stats fast path
**Where:** {{ src("lib/logflare/backends/ingest_event_queue.ex", 198) }} (and lines 263, 417) · **Score:** E4 / S4 / I4 — **4.00**

`list_counts/1` and `list_counts_with_tids/1` have identical bodies. The `add_to_table/3` "no get tid" path strips the count and falls back through `get_tid/1`, so the supposed fast path still pays the mapper-table lookup. Replace with a helper returning `{table_key, tid, size}` and pass `{table_key, tid}` directly into `add_to_table/2`. Or delete the misleading variant.

### 3. No-op short-circuit in `update_all_keys_deep/2`
**Where:** {{ src("lib/logflare/utils/deep_update.ex", 53) }}, {{ src("lib/logflare/logs/ingest_transformers.ex", 8) }} · **Score:** E3 / S3 / I5 (paired with #5) — **4.00**

Always rebuilds each map even when the key function returns every key unchanged. Add copy-on-write: detect whether any key/nested container changed, return the original when nothing changed. When only nested values change, patch with `Map.put/3` so BEAM map sharing preserves unchanged subtrees. Fall back to the current `Enum.map |> Map.new` rebuild on key collisions. **Pair with #5**: alone, the win is small because the existing sanitizer still runs per key.

### 4. Reduce BigQuery resolver source-metrics duplication
**Where:** {{ src("lib/logflare/backends/adaptor/bigquery_adaptor.ex", 84) }}, {{ src("lib/logflare/sources.ex", 420) }} · **Score:** E3 / S4 / I4 — **3.70**

The dynamic-pipeline resolver runs every 2.5s per backend and calls `Sources.refresh_source_metrics_for_ingest/1`. A source with multiple BigQuery backends multiplies identical cache reads. Refresh once per source and share, or wrap a short-TTL cache around the resolver path.

### 5. BigQuery key sanitizer fast path
**Where:** {{ src("lib/logflare/logs/ingest_transformers.ex", 21) }} · **Score:** E3 / S3 / I4 — **3.50**

`to_bigquery_column_spec/1` pipes every key through several rewrite steps. Profiling payloads (OTEL trace, Cloudflare/edge, Phoenix, OTEL metric) show 0 key rewrites in realistic shapes — the common path is paying for safety checks that don't change anything. Add a cheap already-valid-key predicate that returns the original key before the slow path. Consider a one-pass rewrite only after property tests prove equivalence and benchmarks show sanitizer cost is still visible.

### 6. Default-case fast path for `apply_custom_event_message/2`
**Where:** {{ src("lib/logflare/backends.ex", 647) }}, {{ src("lib/logflare/logs/log_event.ex", 272) }} · **Score:** E3 / S3 / I4 — **3.50**

Called for every event. In the common no-custom-message case it can still rewrite `body` and `flattened_body` after `LogEvent.make/2` already built both. Add a fast path that returns the original `%LogEvent{}` when `custom_event_message_keys` is nil and the bodies' `event_message` already match. Longer term, apply event-message before flattening so the flattened body doesn't need patching.

### 7. Use batch-level timestamps in `LogEvent.make/2`
**Where:** {{ src("lib/logflare/logs/log_event.ex", 61) }}, {{ src("lib/logflare/backends.ex", 617) }} · **Score:** E4 / S4 / I3 — **3.50**

Calls `DateTime.utc_now/0` per event for `ingested_at` while `Backends.split_valid_events/2` already computes a batch `now_us`. Events without a timestamp also call `System.system_time/1`. Pass the batch timestamp through `opts`; preserve current behavior when absent.

### 8. Count pending events directly from known queue tids
**Where:** {{ src("lib/logflare/backends/adaptor/bigquery_adaptor.ex", 88) }}, {{ src("lib/logflare/backends/adaptor/clickhouse_adaptor.ex", 483) }}, {{ src("lib/logflare/backends/ingest_event_queue.ex", 393) }} · **Score:** E4 / S4 / I3 — **3.50**

`list_pending_counts/1` traverses the mapper rows, then `total_pending/1` looks the tid up *again* before `:ets.select_count/2`. Count directly from the tids returned by the mapper traversal. Can share the queue-stats helper from #2.

### 12. Remove duplicate `ensure_source_sup_started/1` call
**Where:** {{ src("lib/logflare/logs/processor.ex", 48) }}, {{ src("lib/logflare/backends.ex", 580) }} · **Score:** E5 / S4 / I2 — **3.30**

`Processor.ingest/2` ensures the source supervisor is started, then immediately calls `Backends.ingest_logs/3` which does the same. Drop the call in `Processor.ingest/2`; `Backends.ingest_logs/3` is the shared entrypoint.

### 14. Count valid events once and pass count through dispatch
**Where:** {{ src("lib/logflare/backends.ex", 582) }} (and 691, 748) · **Score:** E4 / S5 / I2 — **3.20**

`ingest_logs/3` counts after splitting; dispatch paths then call `length(log_events)` again for telemetry, repeating list traversal per backend. Return the count from `split_valid_events/2` and thread it through dispatch and telemetry.

### 16. Cache default-ingest backend ids for buffer-full checks
**Where:** {{ src("lib/logflare/backends.ex", 1070) }} · **Score:** E4 / S4 / I2 — **3.00**

`cached_local_pending_buffer_full?/1` builds a `MapSet` of default-ingest backend ids on every request when the feature is enabled. Cache the set with the source/backend cache data instead.

## Tier 2: Measure First or Medium Risk

### 9. Pop non-default backend queues instead of mark-ingested + janitor
**Where:** {{ src("lib/logflare/backends/buffer_producer.ex", 179) }}, {{ src("lib/logflare/backends/ingest_event_queue.ex", 356) }}, {{ src("lib/logflare/backends.ex", 1283) }} · **Score:** E3 / S3 / I4 — **3.50**

The standard fetch path takes pending events, then writes `:ingested` to ETS for each. Several backend ack paths are no-ops, and local recent-log reads use the default `{source_id, nil}` queue rather than non-default backend queues. For non-default backend queues, `pop_pending/2` removes the per-event ETS update and reduces janitor work. Roll out narrowly first.

### 10. Batch source-rule routing instead of recursive single-event ingest
**Where:** {{ src("lib/logflare/sources/source_router.ex", 23) }}, {{ src("lib/logflare/backends.ex", 579) }} (and 724) · **Score:** E2 / S2 / I5 — **3.50**

`SourceRouter.route_to_sinks_and_ingest/3` routes events one at a time, re-entering ingest with a single-event list per matched rule. For rule-heavy sources, every event repeats cache lookups, source-metrics refreshes, supervisor checks, validation plumbing, and dispatch. Accumulate routed events by destination backend or sink source and call `Backends.ingest_logs/3` once per destination batch — preserving `via_rule_id`, counters, and drop semantics.

### 11. Replace Ecto changeset construction in `LogEvent.make/2`
**Where:** {{ src("lib/logflare/logs/log_event.ex", 61) }} · **Score:** E2 / S2 / I5 — **3.50**

Builds a changeset for every event to cast and validate a small known shape. Implement a direct constructor/validator that preserves `pipeline_error` shape, transform ordering, type detection, validation, and flattening. Land lower-risk transform/flattening work first; equivalence risk is real.

### 13. Benchmark ETS mapper-table `read_concurrency`
**Where:** {{ src("lib/logflare/backends/ingest_event_queue.ex", 48) }} · **Score:** E4 / S3 / I3 — **3.30**

The mapper table uses `read_concurrency: false` but is read by `get_tid/1`, queue listing, and dynamic scaling. It's also a `:bag` updated as pipelines start/stop. Benchmark `read_concurrency: true` with realistic ingest contention before flipping it.

### 15. Aggregate buffer lengths in one `BufferCacheWorker` pass
**Where:** {{ src("lib/logflare/backends/ingest_event_queue/buffer_cache_worker.ex", 25) }}, {{ src("lib/logflare/backends.ex", 1006) }} · **Score:** E3 / S4 / I3 — **3.20**

Folds the mapper table for `{source_id, backend_id}` pairs, then calls `Backends.cache_local_buffer_lens/2` per pair (which calls back into queue counting). Aggregate sizes during the fold and cache the lengths directly.

### 17. Preparse drop-filter paths and regexes
**Where:** {{ src("lib/logflare/sources/source_router/sequential.ex", 35) }} (and 111) · **Score:** E3 / S3 / I3 — **3.00**

Source-path drop filters split paths and evaluate regex-like conditions during routing. Cache parsed segments and compiled regexes — or route drop filters through the precompiled rule-tree style used by normal routing.

### 18. Deduplicate backend-rule dispatch if semantics allow
**Where:** {{ src("lib/logflare/backends.ex", 579) }} (and 724), {{ src("lib/logflare/sources/source_router.ex", 25) }} · **Score:** E2 / S2 / I4 — **3.00**

`ingest_logs/3` routes rule matches through `SourceRouter`, then dispatches the original event to the source's directly attached backends. Duplication can occur when the same backend is both directly attached and a rule destination. Add a focused test for the duplication case; if intended behavior is "each event/backend pair ingested once," dedupe by backend id while preserving sink-source routing and `via_rule_id` semantics.

## Tier 3: Opportunistic or Low Priority

### 19. Simplify resolver count math
**Where:** {{ src("lib/logflare/backends.ex", 1103) }}, {{ src("lib/logflare/backends/adaptor/clickhouse_adaptor.ex", 496) }} · **Score:** E5 / S5 / I1 — **3.00**

Both resolvers filter/map queue counts into intermediate lists, then sum separately. Use one reduce to compute `startup_size`, total length, and non-startup threshold state.

### 20. Rework `fetch_events/2` flattening
**Where:** {{ src("lib/logflare/backends/ingest_event_queue.ex", 406) }} (and 537) · **Score:** E4 / S4 / I2 — **2.80**

Not the classic `acc ++ items` O(n²) pattern (the left side is the current chunk). The real issue is the nested list plus `List.flatten/1`. Touch only with a benchmark or while already refactoring queue traversal.

### 21. Fix BigQuery IAM paginator accumulation
**Where:** {{ src("lib/logflare/backends/adaptor/bigquery_adaptor.ex", 519) }} · **Score:** E5 / S4 / I1 — **2.80**

`get_next_page(...) ++ accounts` copies the left side and reverses page order. Management/provisioning path, not ingest. Fix opportunistically.

### 22. Optimize ClickHouse `Array(JSON)` encoding (only with profiling)
**Where:** {{ src("lib/logflare/backends/adaptor/clickhouse_adaptor/native_ingester.ex", 279) }} · **Score:** E2 / S2 / I3 — **2.50**

Nested `Enum.map` encodes JSON values inside each array; output must remain `Array(String)` with the same outer row shape. Do **not** flatten — that corrupts column data. Only optimize JSON encoding cost itself, with profiling evidence.

### 23. Avoid dynamic atoms for Goth partition supervisor names
**Where:** {{ src("lib/logflare/backends/adaptor/bigquery_adaptor.ex", 463) }} · **Score:** E3 / S4 / I1 — **2.20**

`String.to_atom("Logflare.GothPartitionSup_#{i}")` is bounded by `managed_service_account_pool_size` so leak risk is low under controlled config. Prefer Registry-compatible naming if this area is refactored, or at minimum validate the configured pool size.

### 24. Defer eager `Mimic.copy` at test boot
**Where:** {{ src("test/test_helper.exs", 5) }} · **Score:** E2 / S2 / I1 — **1.50**

Dev-experience work. Mimic setup ordering and module loading make broad migration invasive — measure boot cost first, then move a small cluster of rarely used mocks.

### 25. Split `dialect_translation.ex`
**Where:** {{ src("lib/logflare/sql/dialect_translation.ex") }} · **Score:** E1 / S2 / I1 — **1.20**

Maintainability concern, not performance. BigQuery↔PostgreSQL translation, parameter extraction, and helpers are all in one large module. Touch only when already making functional changes here.

!!! note "Already slated for removal"
    Dialect translation is on the [Legacy & Deprecated](legacy.md#sql-dialect-translation-bigquery-postgresql) list — splitting the module is wasted effort if the whole subsystem is being retired.

## Recommended Execution Order

1. **Flatten hot path** — #1
2. **Queue dispatch fast path** — #2, then reuse the queue-stats helper for #8
3. **Key-transform no-op path** — #5 first, then #3, guarded by equivalence property tests
4. **Low-risk per-event cleanup** — #6, #7, #14
5. **Request/background cleanup** — #12, #4, #16, #19
6. **Measure before changing semantics** — #9, #13, #15
7. **Strategic hot-path work** — #10 and #11 only after the quick wins and benchmarks identify remaining bottlenecks
8. **Opportunistic** — #20, #21, #22, #23, #24, #25 only when already in the area or when profiling points there

## Benchmarking

Three layers — prove local wins first, then verify they survive the realistic ingest path. Run before/after on the same machine with the same `MIX_ENV`; prefer reduction/memory deltas over small ips swings when variance is high.

### Layer 1 — transform & `LogEvent.make/2` hot path

Primary harness for #1, #3, #5, #6, #7, #11.

```bash
MIX_ENV=test mix run test/profiling/transform_bench.exs
MIX_ENV=test mix run test/profiling/log_event_make_bench.exs
MIX_ENV=test mix run test/profiling/log_event_make_type_detection_bench.exs
```

`transform_bench.exs` is the tight synthetic harness — baseline vs. parsed/unparsed `copy_fields`, `kv_enrich`, `drop_fields`, and combined transforms. `log_event_make_bench.exs` (PR 3449's expanded scenarios) is the realistic one — OTEL trace and edge-log payloads, sources fetched via `Sources.Cache.get_by_and_preload_rules/1`, scenarios across no-transform / copy / kv / drop / copy+kv / all.

For function-level attribution add a small benchmark that calls `MetadataCleaner.flatten/1`, `EnumDeepUpdate.update_all_keys_deep/2`, `IngestTransformers.transform/2`, and `LogEvent.apply_custom_event_message/2` directly against the same payloads — `LogEvent.make/2` blends several costs together.

### Layer 2 — queue & ETS paths

Primary harness for #2, #8, #9, #13, #15, #20.

```bash
MIX_ENV=test mix run test/profiling/ingest_event_queue_add_to_table_bench.exs
MIX_ENV=test mix run test/profiling/ingest_event_queue_list_bench.exs
MIX_ENV=test mix run test/profiling/ingest_event_queue_traverse_queues_bench.exs
MIX_ENV=test mix run test/profiling/ingest_event_queue_counts.exs
```

`add_to_table_bench` is the right script for #2. `list_bench` covers `list_counts*`/`list_queues*` variants — use it for #2, #8, #15. `traverse_queues_bench` for #20. `counts.exs` has stale assumptions; clean up before relying on its numbers.

To test `read_concurrency` (#13) well, add a variant with concurrent readers/writers — current scripts are mostly single-process Benchee runs and miss contention effects. To test #9, simulate backend producer fetches plus janitor cleanup volume.

### Layer 3 — routing & end-to-end

Use only after narrower benchmarks show a win or production evidence points at routing.

```bash
MIX_ENV=test mix run test/profiling/source_routing_bench.exs
```

Also: `test/profiling/ingest_http.exs`, `ingest_http_api_plugs.exs`, `ingest_http_plugs.exs`, `ingest_logs.exs`. Some use hardcoded source tokens or local DB assumptions — verify before relying on output. Most relevant for #10, #17, #18, plus aggregate-impact checks after Layer 1/2 wins.

### Acceptance criteria

| Tier | Required |
|------|----------|
| 1 | No correctness regression in the relevant full test file; clear runtime/reduction/memory improvement in the targeted script; no regression in the realistic `LogEvent.make/2` or queue benchmark covering the same path |
| 2 | A measurable benchmark win **or** an independent correctness/resource-saving justification |
| 3 | Benchmark only when already touching the area, or when production evidence points there |
