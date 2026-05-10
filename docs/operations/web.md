# Web Layer

The web layer uses [Phoenix](https://www.phoenixframework.org/) with [LiveView](https://hexdocs.pm/phoenix_live_view/) for real-time UI and a REST API documented with [OpenApiSpex](https://hexdocs.pm/open_api_spex/).

## Pipelines

| Pipeline | Purpose | Auth |
|----------|---------|------|
| `:browser` | Dashboard UI (LiveView) | Session-based, team/plan context |
| `:api` | REST API (JSON/BERT) | None (auth added by composing with `:require_*` pipelines) |
| `:otlp_api` | OTLP ingestion (Protobuf) | API key |
| `:require_ingest_api_auth` | Log ingestion | API key + rate limiting + buffer limiting |
| `:require_mgmt_api_auth` | Management API | Private-scoped API key |
| `:partner_api` | Partner integrations | Partner-scoped API key |

## OAuth2

Logflare acts as an OAuth2 provider (via [PhoenixOauth2Provider](https://hexdocs.pm/phoenix_oauth2_provider/)) for integrations with Vercel and Cloudflare.

## Real-Time Features

- **LiveView dashboard** — real-time log tailing, source management, endpoint testing
- **PubSub rates** — ingestion rates broadcast via [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub/) for live UI updates
- **Active user tracking** — presence tracking for connected dashboard users
