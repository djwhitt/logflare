# credo:disable-for-this-file Credo.Check.Refactor.IoPuts
#
# Usage: MIX_ENV=test mix run test/profiling/log_event_make_bench.exs
#
# Env:
#   SAVE_SNAPSHOT=1     — append this run's results to log_event_make_bench.history.exs
#   LABEL="..."         — optional label for the new entry (e.g., "post X rewrite")
#   MACHINE="..."       — optional machine identifier so cross-machine entries can be filtered
#   PROFILE=1           — run :tprof against each scenario after the benchmark (Benchee profile_after)
#   TPROF_TYPE=time     — :tprof type when PROFILE=1 (time | calls | memory; default time)
#
# Every run prints a delta table vs the most-recent entry in the history file
# (if one exists). The history file is the source of truth for trend tracking.

alias Logflare.LogEvent
alias Logflare.Profiling

import Logflare.Factory

# Setup test data
user = insert(:user)
source = insert(:source, user: user)

# OTEL trace payload (~15 leaf values, 2-3 levels deep)
otel_trace_params = %{
  "attributes" => %{
    "_client_address" => "2600:1fc4:22a5:ae73:2887:684b:66c0:1f85",
    "_http_request_method" => "POST",
    "_http_route" => "/functions/v1/*path",
    "_http_status_code" => 404,
    "_network_peer_address" => "99.88.160.11",
    "_network_peer_port" => 57_785,
    "_network_protocol_version" => "1.1",
    "_server_address" => "supabase-api-gateway",
    "_url_path" => "/functions/v1/stripe-worker",
    "_url_scheme" => "https",
    "_user_agent_original" => "pg_net/0.19.5"
  },
  "end_time" => "2026-01-21T17:54:48.444334Z",
  "event_message" => "POST /functions/v1/*path",
  "metadata" => %{"type" => "span"},
  "project" => "supabase-api-gateway",
  "resource" => %{
    "cloud" => %{"region" => "us-east-1"},
    "deployment" => %{"environment" => "staging"},
    "service" => %{"name" => "supabase-api-gateway", "version" => "1.0.0"}
  },
  "scope" => %{
    "name" => "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin",
    "version" => "0.61.0"
  },
  "span_id" => "c99f33f1bfa4fb8f",
  "start_time" => "2026-01-21T17:54:48.144506Z",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "trace_id" => "f9918d38f5d1cb74ec5656b9a315e5f6"
}

# Edge log payload (~80 leaf values, 4-5 levels deep).
#
# NOTE: the `cf` subtree (botManagement + ja4Signals + tlsClientAuth) overstates
# the current production shape — those subtrees have been trimmed upstream. We
# keep the original shape here so existing history entries remain comparable.
# When refreshing baselines, trim cf to match prod and reseed the history file.
edge_log_params = %{
  "event_message" =>
    "POST | 200 | 3.254.227.51 | 9ca90d4f3f7cc99e | https://example.supabase.co/rest/v1/calls",
  "id" => "3701391c-dead-405d-9943-61cc7576da87",
  "identifier" => "example_project",
  "metadata" => %{
    "logflare_worker" => %{"worker_id" => "ZZ79SS"},
    "request" => %{
      "cf" => %{
        "asOrganization" => "Amazon Data Services Ireland Limited",
        "asn" => 16_509,
        "botManagement" => %{
          "corporateProxy" => false,
          "ja3Hash" => "a1465cad7ff59adb0e36ccd6339ba5db",
          "ja4" => "t23e1011h2_61a7dd8aa9b6_3fcd1a44f3e3",
          "ja4Signals" => %{
            "browser_ratio_1h" => 0.0026,
            "cache_ratio_1h" => 0.0389,
            "h2h3_ratio_1h" => 0.9899,
            "heuristic_ratio_1h" => 0.2229,
            "ips_quantile_1h" => 0.9997,
            "ips_rank_1h" => 218,
            "paths_rank_1h" => 16,
            "reqs_quantile_1h" => 0.9999,
            "reqs_rank_1h" => 36,
            "uas_rank_1h" => 294
          },
          "jsDetection" => %{"passed" => false},
          "score" => 46,
          "staticResource" => false,
          "verifiedBot" => false
        },
        "city" => "Dublin",
        "clientAcceptEncoding" => "gzip, br",
        "clientTcpRtt" => 4,
        "clientTrustScore" => 46,
        "colo" => "DUB",
        "continent" => "EU",
        "country" => "IE",
        "edgeRequestKeepAliveStatus" => 1,
        "httpProtocol" => "HTTP/2",
        "latitude" => "53.33326",
        "longitude" => "-6.24789",
        "postalCode" => "D02",
        "region" => "Leinster",
        "regionCode" => "L",
        "requestPriority" => "weight=16;exclusive=0",
        "timezone" => "Europe/Dublin",
        "tlsCipher" => "AEAD-AES256-GCM-SHA384",
        "tlsClientAuth" => %{
          "certPresented" => "0",
          "certRevoked" => "0",
          "certVerified" => "NONE"
        },
        "tlsVersion" => "TLSv1.3"
      },
      "headers" => %{
        "accept" => "*/*",
        "cf_connecting_ip" => "3.254.227.51",
        "cf_ipcountry" => "IE",
        "cf_ray" => "9ca90d4f3f7cc99e",
        "content_length" => "18466",
        "content_type" => "application/json",
        "host" => "example.supabase.co",
        "user_agent" => "Deno/2.1.4"
      },
      "host" => "example.supabase.co",
      "method" => "POST",
      "path" => "/rest/v1/calls",
      "protocol" => "https:",
      "search" => "?on_conflict=call_id",
      "url" => "https://example.supabase.co/rest/v1/calls?on_conflict=call_id"
    },
    "response" => %{
      "headers" => %{
        "cf_cache_status" => "DYNAMIC",
        "cf_ray" => "ba903a6f47bfc12f-DUB",
        "content_length" => "0",
        "date" => "Tue, 16 Dec 2025 18:26:18 GMT",
        "sb_gateway_version" => "1"
      },
      "origin_time" => 12,
      "status_code" => 200
    }
  },
  "project" => "example_project",
  "request_id" => "a99b2a69-dead-752e-78bb-14ca90530fe1",
  "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
}

profile_after =
  if System.get_env("PROFILE") == "1" do
    type = String.to_existing_atom(System.get_env("TPROF_TYPE") || "time")
    {:tprof, type: type, warmup: 0, sort: :per_call}
  else
    false
  end

suite =
  Benchee.run(
    %{
      "otel trace" => fn ->
        LogEvent.make(otel_trace_params, %{source: source})
      end,
      "edge log" => fn ->
        LogEvent.make(edge_log_params, %{source: source})
      end
    },
    time: 5,
    warmup: 2,
    memory_time: 3,
    reduction_time: 3,
    profile_after: profile_after
  )

history_path = Path.expand("log_event_make_bench.history.exs", __DIR__)
Profiling.track(suite, history_path)
