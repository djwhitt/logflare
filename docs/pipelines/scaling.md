# Dynamic Pipeline Scaling

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

Currently used by the ClickHouse consolidated pipeline and the BigQuery adaptor.
