# Home Assistant history fetch benchmark

This read-only benchmark compares equivalent fixed time windows and entity
lists through:

1. the REST history endpoint;
2. the finite WebSocket `history/history_during_period` command from the
   supplied Gemini example; and
3. the `history/stream` subscription shape currently used by NativeHA.

It reports connection/authentication time, server-plus-receive wait, JSON
decode time, response size, sample count, and stream chunk count. For the
ongoing stream, it stops after the first non-empty replay event: this is the
point at which NativeHA publishes graph data and changes the owner from loading
to ready. Payloads and the access token are never saved. The default token path
and server candidates match `Sources/NativeHAMac/AppConfig.swift`; override
them with `HA_TOKEN`, `--token-file`, or repeated `--base-url` arguments.

The measured byte count is the decoded UTF-8 WebSocket message size, matching
the Gemini script's `len(msg)` idea. It is not a packet capture and does not
measure WebSocket compression. Python JSON decode timings are not Swift JSON
decode timings. REST cannot separate HTTP connection setup from server/receive
time in this harness, so its `wait` column includes both; WebSocket connection
and authentication are reported separately.

For equivalent comparisons, the benchmark always supplies explicit entity
IDs. Its REST shape matches `HomeAssistantRESTClient.fetchHistory`
(`minimal_response` plus `significant_changes_only=0`). WebSocket requests also
set `no_attributes=true`, matching NativeHA for these sensor entities, so REST
and WebSocket sample counts are comparable but their payload representations
and byte counts are not identical.

For local Swift decode profiling, capture one stream event outside the
repository, then run the companion benchmark. The payload contains entity
history but no access token:

```sh
python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 12 --runs 1 --methods ws_stream \
  --capture-stream-frame /tmp/nativeha-history-event.json

swift run -c release HistoryFetchDecodeBench \
  /tmp/nativeha-history-event.json
```

Examples:

```sh
python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 12 --runs 3 \
  --output-json Benchmarks/HistoryFetch/results-12h-four-sps30.json

python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 336 --runs 3 --entities sensor.sps30_pm2_5 \
  --methods rest ws_period \
  --output-json Benchmarks/HistoryFetch/results-14d-pm25.json
```

Do not compare an all-entity request with an SPS30-only request. Omitting
`entity_ids` from `history/history_during_period`, as in the supplied fragment,
requests all recorded entities and changes both server work and payload size.
