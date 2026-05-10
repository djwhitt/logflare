# Deployment Modes

## Multi-Tenant (SaaS)

Full-featured mode with:

- User/team management and billing ([Stripe](https://stripe.com/docs/api) integration)
- Feature flags via [ConfigCat](https://configcat.com/docs/)
- Cluster discovery via [libcluster](https://hexdocs.pm/libcluster/)
- Google Cloud service accounts for BigQuery (via [Goth](https://hexdocs.pm/goth/))
- Partner integrations (Vercel)

## Single-Tenant

Simplified deployment with:

- Auto-seeded default user and plan
- Optional **Supabase mode** — creates predefined sources and endpoints for Supabase log routing
- Optional PostgreSQL-only backend (no BigQuery dependency)
- Controlled via `Logflare.SingleTenant.single_tenant?/0`
