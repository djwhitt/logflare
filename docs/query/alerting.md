# Alerting

The alerting system executes SQL queries on a cron schedule and sends notifications when results are non-empty.

```mermaid
flowchart TB
    CRON["Oban Cron<br/>(AlertSchedulerWorker)"] -->|"schedule"| JOBS["AlertWorker Jobs"]
    JOBS -->|"execute"| EXP["Sql.expand_subqueries<br/>(endpoints + alerts as CTEs)"]
    EXP --> TX["Sql.transform"]
    TX --> EXEC["BigQueryAdaptor.execute_query"]
    EXEC -->|"results?"| CHECK{"Non-empty?"}
    CHECK -->|"yes"| NOTIFY["Notifications"]
    CHECK -->|"no"| DONE["Done"]
    NOTIFY --> WH["Webhook"]
    NOTIFY --> SL["Slack"]
    NOTIFY --> BA["Backend-specific<br/>(adaptor.send_alert/3)"]
```

Alerts share the SQL transformation utilities ({{ mod("Logflare.Sql") }}) with [Endpoints](index.md) but **execute directly against BigQuery** via `BigQueryAdaptor.execute_query` — they do not go through `Endpoints.run_query/3` or the endpoint result cache. Subquery expansion still inlines references to other endpoints and alerts as CTEs.

Scheduling and history are managed via [Oban](https://hexdocs.pm/oban/) job queues:

- `schedule_alert/1` parses the cron expression, generates the next 5 run dates, and inserts Oban jobs
- `trigger_alert_now/1` allows immediate manual execution
- Execution history (last 50 runs) and future jobs are queryable
