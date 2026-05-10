# Supervision Tree

The Logflare runtime is rooted at `Logflare.Supervisor` (`one_for_one`). Children are organised by responsibility — networking, conditional services, core infrastructure, caches, backends, web endpoints, and telemetry.

The supervision tree is large enough that a single diagram becomes illegible at content-area width. The diagrams below split the tree by branch, with the top-level overview as a map and each subsequent diagram zooming into one branch.

!!! note "Diagram color legend"
    All diagrams on this page use a consistent palette:

    - <span style="background:#4a90d9;color:#fff;padding:2px 6px">supervisor</span> — `Supervisor` or `PartitionSupervisor`
    - <span style="background:#6bb86b;color:#fff;padding:2px 6px">dynamic</span> — `DynamicSupervisor` or dynamically-started children
    - <span style="background:#d9534f;color:#fff;padding:2px 6px">registry</span> — `Registry` process
    - <span style="background:#f0ad4e;color:#fff;padding:2px 6px">conditional</span> — started only when configuration enables it

## Top-level overview

`Logflare.Supervisor` directly supervises 14+ children. The diagram below collapses each major branch to a single labeled node — see the per-branch diagrams further down for detail.

```mermaid
graph TD
    Root["Logflare.Supervisor<br/><i>one_for_one</i>"]

    Root --> Networking["Finch Pools<br/><i>networking/HTTP clients</i>"]
    Root --> Conditional["Conditional services<br/><i>Goth, ConfigCat, OTel exporter</i>"]
    Root --> Core["Core infrastructure<br/><i>Repo, Vault, Oban, PubSub,<br/>ErlSysMon, ClusterSup, TaskSups</i>"]
    Root --> CCSup["ContextCache.Supervisor"]
    Root --> CountersGrp["Counters &amp; rates<br/><i>Counters, RateCounters,<br/>PubSubRates, LogEventsCache,<br/>RejectedLogEvents</i>"]
    Root --> BackendsSup["Backends.Supervisor"]
    Root --> SourceSupervisor["Sources.Source.Supervisor<br/><i>per-source lifecycle GenServer</i>"]
    Root --> WebEndpoint["LogflareWeb.Endpoint"]
    Root --> GRPCSup["GRPC.Server.Supervisor"]
    Root --> SysMet["SystemMetricsSup"]
    Root --> Telemetry["Logflare.Telemetry"]
    Root --> EndpointsPSup["PartitionSupervisor<br/>:Endpoints.ResultsCache"]
    Root --> StartupTask["Task<br/><i>startup_tasks/0</i>"]
    Root --> ActiveUserTracker["ActiveUserTracker"]

    classDef supervisor fill:#4a90d9,stroke:#2c5f8a,color:#fff
    classDef dynamic fill:#6bb86b,stroke:#3d7a3d,color:#fff
    classDef conditional fill:#f0ad4e,stroke:#c77c25,color:#fff

    class Root,CCSup,BackendsSup,SysMet supervisor
    class EndpointsPSup dynamic
    class Conditional conditional
```

**Key ordering constraints:**

- `Repo` and `Vault` start before any child that touches the database
- `Backends.Supervisor` starts before `Sources.Source.Supervisor` (backends register queues that sources write to)
- `Counters` starts before `Sources.Source.Supervisor` (sources call counters during init)

## Networking — Finch pools

Seven named [Finch](https://hexdocs.pm/finch/) connection pools serve different traffic classes. They are listed by `Networking.pools/0` and started directly under the root.

```mermaid
graph TD
    FinchPools["Finch Pools<br/><i>from Networking.pools/0</i>"]
    FinchPools --> FinchGoth["Finch :FinchGoth"]
    FinchPools --> FinchHttp1["Finch :FinchDefaultHttp1"]
    FinchPools --> FinchGoogleApi["Finch :GoogleApiClient"]
    FinchPools --> FinchIngest["Finch :FinchIngest"]
    FinchPools --> FinchQuery["Finch :FinchQuery"]
    FinchPools --> FinchDefault["Finch :FinchDefault"]
    FinchPools --> FinchCH["Finch :FinchClickHouseIngest"]
```

## Conditional services

These are only started when their corresponding configuration is present.

```mermaid
graph TD
    Cond["Conditional"]
    Cond -.->|"if BigQuery configured"| Goth["PartitionSupervisor :Goth"]
    Cond -.->|"if config_cat_sdk_key"| ConfigCatCache["ConfigCatCache"]
    Cond -.->|"if config_cat_sdk_key"| ConfigCat["ConfigCat"]
    Cond -.->|"from UserMonitoring"| OtelExporter["OTel Exporter"]

    classDef conditional fill:#f0ad4e,stroke:#c77c25,color:#fff
    class Cond,Goth,ConfigCat,ConfigCatCache,OtelExporter conditional
```

## ContextCache supervisor

`ContextCache.Supervisor` (`one_for_one`) owns the read-through caches and the WAL-based cache invalidation pipeline. See [Caching](caching.md) for the read-through behaviour.

```mermaid
graph TD
    CCSup["ContextCache.Supervisor<br/><i>one_for_one</i>"]
    CCSup --> Caches["Cachex Caches<br/><i>TeamUsers, Partners, Users,<br/>Backends, Sources, Billing,<br/>SourceSchemas, Auth, Endpoints,<br/>Rules, KeyValues, SavedSearches</i>"]
    CCSup --> TxBroadcaster["TransactionBroadcaster"]
    CCSup --> GenSingleton["GenSingleton<br/><i>wraps Cainophile.Adapters.Postgres</i>"]
    CCSup --> CBWorkerSup["CacheBusterWorker Supervisor"]
    CCSup --> CacheBuster["CacheBuster"]

    classDef supervisor fill:#4a90d9,stroke:#2c5f8a,color:#fff
    class CCSup,CBWorkerSup supervisor
```

## Backends supervisor

`Backends.Supervisor` (`one_for_one`) owns ingestion-side infrastructure: the event queue, registries, the per-source partition supervisor, and adaptor-specific support processes. ClickHouse-specific connection management is split into a separate diagram below for legibility.

```mermaid
graph TD
    BackendsSup["Backends.Supervisor<br/><i>one_for_one</i>"]
    BackendsSup --> IEQ["IngestEventQueue"]
    BackendsSup --> BufferCache["IngestEventQueue.BufferCacheWorker"]
    BackendsSup --> MapperJanitor["IngestEventQueue.MapperJanitor"]

    BackendsSup --> PgSup["PostgresAdaptor.Supervisor<br/><i>one_for_one</i>"]
    PgSup --> PgRepos["DynamicSupervisor :Repos<br/><i>dynamic Ecto repos</i>"]

    BackendsSup --> ConsolidatedSup["ConsolidatedSup<br/><i>one_for_one</i>"]
    ConsolidatedSup --> ConsDynSup["DynamicSupervisor<br/><i>consolidated pipelines</i>"]
    ConsolidatedSup --> ConsWorker["ConsolidatedSupWorker<br/><i>reconciliation</i>"]

    BackendsSup --> SourcesSup["PartitionSupervisor<br/>:Backends.SourcesSup<br/><i>child: DynamicSupervisor</i>"]
    BackendsSup --> SourceRegistry["Registry :SourceRegistry"]
    BackendsSup --> BackendRegistry["Registry :BackendRegistry"]

    BackendsSup --> CHGroup["ClickHouse support<br/><i>see below</i>"]

    classDef supervisor fill:#4a90d9,stroke:#2c5f8a,color:#fff
    classDef dynamic fill:#6bb86b,stroke:#3d7a3d,color:#fff
    classDef registry fill:#d9534f,stroke:#a94442,color:#fff

    class BackendsSup,PgSup,ConsolidatedSup supervisor
    class PgRepos,ConsDynSup,SourcesSup dynamic
    class SourceRegistry,BackendRegistry registry
```

### ClickHouse-specific support processes

The ClickHouse adaptor adds connection pooling, schema caching, and mapping config storage as direct children of `Backends.Supervisor`.

```mermaid
graph TD
    BackendsSup["Backends.Supervisor"]
    BackendsSup --> MappingConfigStore["CH MappingConfigStore"]
    BackendsSup --> NativeSchemaCache["CH NativeIngester.SchemaCache"]

    BackendsSup --> PoolSup["CH NativeIngester.PoolSup<br/><i>one_for_one</i>"]
    PoolSup --> PoolDynSup["DynamicSupervisor<br/><i>Pool instances</i>"]
    PoolSup --> ManagerDynSup["DynamicSupervisor<br/><i>PoolManager instances</i>"]

    BackendsSup --> QueryConnSup["CH QueryConnectionSup<br/><i>one_for_one</i>"]
    QueryConnSup --> QueryDynSup["DynamicSupervisor<br/><i>ConnectionManager instances</i>"]

    classDef supervisor fill:#4a90d9,stroke:#2c5f8a,color:#fff
    classDef dynamic fill:#6bb86b,stroke:#3d7a3d,color:#fff

    class BackendsSup,PoolSup,QueryConnSup supervisor
    class PoolDynSup,ManagerDynSup,QueryDynSup dynamic
```

## Per-source `SourceSup`

`SourceSup` is a `one_for_one` supervisor spawned dynamically for each active source under `PartitionSupervisor :Backends.SourcesSup`. It owns per-source workers (rate counters, notification servers, billing) and one adaptor child per backend (for non-consolidated backends; consolidated backends run under `ConsolidatedSup` instead).

```mermaid
graph TD
    SourcesSup["PartitionSupervisor<br/>:Backends.SourcesSup<br/><i>child: DynamicSupervisor</i>"]
    SourcesSup -.->|"dynamic"| SourceSup["SourceSup<br/><i>per source, one_for_one</i>"]
    SourceSup --> RateCounterServer["RateCounterServer"]
    SourceSup --> RecentInserts["RecentInsertsCacher"]
    SourceSup --> EmailNotif["EmailNotificationServer"]
    SourceSup --> TextNotif["TextNotificationServer"]
    SourceSup --> WebhookNotif["WebhookNotificationServer"]
    SourceSup --> SlackHook["SlackHookServer"]
    SourceSup --> BillingWriter["BillingWriter"]
    SourceSup --> SourceSupWorker["SourceSupWorker"]
    SourceSup -.->|"per backend"| AdaptorChild["Backend Adaptor<br/><i>non-consolidated only</i>"]

    classDef supervisor fill:#4a90d9,stroke:#2c5f8a,color:#fff
    classDef dynamic fill:#6bb86b,stroke:#3d7a3d,color:#fff

    class SourceSup supervisor
    class SourcesSup,AdaptorChild dynamic
```

The adaptor child itself starts an `AdaptorSupervisor` containing the backend's `QueueJanitor` and `Pipeline` (Broadway) — see [Broadway Pipelines](../pipelines/broadway.md) and [Backpressure → Layer 3](../pipelines/backpressure.md#layer-3-queuejanitor).

## System metrics

`SystemMetricsSup` (`one_for_one`) hosts the metric counters and pollers that surface telemetry to the rest of the system.

```mermaid
graph TD
    SysMet["SystemMetricsSup<br/><i>one_for_one</i>"]
    SysMet --> AllLogsLogged["AllLogsLogged"]
    SysMet --> AllLogsLoggedPoller["AllLogsLogged.Poller"]
    SysMet --> TelPoller[":telemetry_poller<br/><i>Observer, Cluster,<br/>Schedulers, Finch</i>"]

    classDef supervisor fill:#4a90d9,stroke:#2c5f8a,color:#fff
    class SysMet supervisor
```
