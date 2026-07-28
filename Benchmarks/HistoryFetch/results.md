# Recorded history-fetch results

## 2026-07-28 — current local Home Assistant deployment

Machine: Joy's MBP (2). Server selected by the benchmark:
`http://joyj.me:8123`. All operations were read-only. WebSocket diagnostic
logging was at the production `warning` threshold, so full history frames were
not being persisted while timing.

The Python benchmark fixes one start/end window for each invocation and uses
the same explicit entity list for REST and finite WebSocket requests.
`history/stream` deliberately omits `end_time`, matching NativeHA and
hass-frontend, and stops timing at its first non-empty replay event—the point
where NativeHA first publishes graph data and reports the owner ready.
Consequently, small sample-count increases in successive stream runs are live
updates, not a finite-response mismatch.

REST uses NativeHA's current REST query shape: `minimal_response` and
`significant_changes_only=0`. The sensor WebSocket requests additionally use
`no_attributes=true`, matching NativeHA's production stream policy. Counts are
comparable; payload bytes are not a claim that the representations are
identical. REST's server/receive column includes HTTP connection setup because
the standard-library harness cannot separate it.

### Current live CO2/VOC card, 12 hours

Entities:

- `sensor.qtpy_air_quality_bme688_iaq`
- `sensor.qtpy_air_quality_scd41_co2`
- `sensor.sps30_pm2_5`
- `sensor.sps30_pm1_0`

Python protocol results, three runs:

| Method | Samples | Decoded payload | Mean total | Mean server/receive | Mean Python JSON decode |
|---|---:|---:|---:|---:|---:|
| finite WebSocket `history/history_during_period` | 102,437–102,444 | 4.71 MiB | 1.034 s | 0.970 s | 0.039 s |
| production-shaped WebSocket `history/stream` | 102,437–102,453 | 4.71 MiB | 0.784 s | 0.718 s | 0.038 s |

Command:

```sh
python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 12 --runs 3 --methods ws_period ws_stream \
  --entities \
    sensor.qtpy_air_quality_bme688_iaq \
    sensor.qtpy_air_quality_scd41_co2 \
    sensor.sps30_pm2_5 \
    sensor.sps30_pm1_0 \
  --output-json Benchmarks/HistoryFetch/results-12h-live-card.json
```

Before the optimization, NativeHA's release live smoke against the same card
published 102,433 points in **4.735 s**. A debug-build repetition published
102,443 points in **4.543 s**. Both passed correctness and connection-ownership
checks.

```sh
NATIVEHA_RUN_LIVE_HISTORY_SMOKE=1 \
swift test -c release \
  --filter HomeAssistantHistoryLiveSmokeTests.testReadOnlyOneHourTwelveHourTwentyFourHourAndReconnectSmoke
```

The large difference was locally explained by NativeHA's decoding path. For a
captured 4,940,017-byte, 102,418-sample stream event, five release iterations
measured before implementation:

| Swift stage | Mean | Median |
|---|---:|---:|
| current generic `JSONValue` decode → encode event again → typed decode | 3.601 s | 3.600 s |
| direct typed event-envelope decode | 0.386 s | 0.386 s |
| compact history → current string-timestamp graph projection | 0.564 s | 0.564 s |

The direct typed decode was **9.33× faster** and avoided **3.215 s** of CPU per
replay in this fixture. Adding the independently measured stream wait
(approximately 0.7–0.9 s) to the current 3.6 s decode closely predicts the
observed 4.5–4.7 s NativeHA publication time. This is a diagnosis from adjacent
runs, not a single instrumented wall-clock decomposition.

```sh
python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 12 --runs 1 --methods ws_stream \
  --entities \
    sensor.qtpy_air_quality_bme688_iaq \
    sensor.qtpy_air_quality_scd41_co2 \
    sensor.sps30_pm2_5 \
    sensor.sps30_pm1_0 \
  --capture-stream-frame /tmp/nativeha-history-event.json

swift run -c release HistoryFetchDecodeBench \
  /tmp/nativeha-history-event.json
```

### Four SPS30 series, 12 hours

Three-run means:

| Method | Samples | Decoded payload | Mean total | Mean server/receive | Mean Python JSON decode |
|---|---:|---:|---:|---:|---:|
| REST | 166,899–166,915 | 12.68 MiB | 2.187 s | 2.121 s | 0.065 s |
| finite WebSocket | 166,915 | 7.77 MiB | 1.327 s | 1.238 s | 0.064 s |
| production-shaped stream | 166,919–166,959 | 7.77 MiB | 1.474 s | 1.386 s | 0.061 s |

The finite command is faster than REST here, but it is not materially faster
than the stream that NativeHA already requests. Changing endpoint alone cannot
explain or remove the app's several-second delay.

```sh
python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 12 --runs 3 \
  --output-json Benchmarks/HistoryFetch/results-12h-four-sps30.json
```

### SPS30 PM2.5, 14 days

One entity, 1,145,171–1,145,293 samples. The first REST and finite-WebSocket
runs were cold outliers; warm means below use runs two and three.

| Method | Decoded payload | First total | Warm mean total | Warm mean server/receive | Mean Python JSON decode |
|---|---:|---:|---:|---:|---:|
| REST | 86.29 MiB | 48.996 s | 12.574 s | 12.165 s | 0.423 s |
| finite WebSocket | 52.64 MiB | 16.878 s | 8.941 s | 8.444 s | 0.410 s |
| production-shaped stream | 52.65 MiB | 8.556 s | 8.189 s | 7.741 s | 0.410 s |

```sh
python3 Benchmarks/HistoryFetch/benchmark_history_fetch.py \
  --hours 336 --runs 3 \
  --entities sensor.sps30_pm2_5 \
  --output-json Benchmarks/HistoryFetch/results-14d-pm25.json
```

This confirms the user's roughly ten-second WebSocket observation for an
equivalent one-entity request. NativeHA was not asked to ingest this replay:
its configured incoming-message limit is 32 MiB, while this event is over
52 MiB. The Python benchmark used a 256 MiB limit. The supplied Gemini fragment
used 50 MiB, slightly below this particular payload, so its success depends on
the exact time window/data size or a different effective limit.

The supplied fragment also omitted `entity_ids`. That means **all recorded
entities**, not SPS30. An all-entity result is not comparable to the explicit
SPS30 measurements above and may exceed the fragment's message limit.

### Implemented result

NativeHA now scans only the lightweight WebSocket envelope, copies the selected
event bytes, and decodes the requested type on the existing bounded per-owner
delivery worker. It keeps the generic `JSONValue` route for commands, raw
subscriptions, extended envelopes, and mixed coalesced frames. Typed delivery
still preserves per-owner wire order, the four-task global callback bound,
bounded buffers, cancellation, reconnect generation checks, complete debug
frame logging, and the production URLSession transport.

The graph projection also retains compact timestamps as numeric seconds.
Legacy `HAHistoryPoint` string access and Codable remain compatible and format
on demand, while graph preparation consumes the numeric values directly.

On the same captured event after implementation:

| Swift stage | Mean | Median |
|---|---:|---:|
| retained generic → re-encode → typed comparison path | 3.633 s | 3.631 s |
| direct typed event-envelope decode | 0.387 s | 0.386 s |
| compact history → numeric-timestamp graph projection | 0.060 s | 0.059 s |

Direct typed decoding was **9.40× faster** than the retained comparison path,
and projection was about **9.4× faster** than its 0.564-second pre-change
measurement.

Two post-change release live-smoke repetitions published 102,480–102,481 CO2/VOC
points for 12 hours in **1.397–1.485 s**, versus 4.735 s before. That is a
measured **3.19–3.39× end-to-end speedup**. The complete read-only smoke also
passed 1-hour, 24-hour, reconnect, ownership, no-attributes, and fractional
timestamp checks.

## Conclusions and remaining prioritized experiments

1. **Keep `history/stream` for visible graphs.** The server benchmark does not
   show a finite-command advantage over the production-shaped stream for the
   live card, and the stream supplies ongoing updates. Switching endpoints is
   therefore lower value than fixing local decode. A finite command remains
   useful for explicitly bounded backfill/cache jobs.

2. **For multi-day ranges, backfill in bounded chunks and publish newest data
   first.** A 14-day single-entity event already exceeds NativeHA's 32 MiB
   safety limit. Fetching daily or otherwise size-bounded windows can retain
   that safety boundary, display the newest viewport quickly, and merge older
   windows progressively. Benchmark bounded concurrency (for example two
   requests) against Home Assistant recorder load before selecting it.

3. **Implement the already-approved coverage-aware cache and idle prefetch.**
   Reuse a cached 24-hour range for contained 1/3/6/12-hour views, fetch only
   missing coverage, and deduplicate foreground/detail requests. This removes
   repeat waits rather than merely making every repeat cheaper.

4. **Benchmark request consolidation.** NativeHA currently owns history per
   card/request. Combining visible-card entity IDs into one replay may reduce
   recorder queries and duplicate work, but a single larger frame increases
   memory and failure scope. Compare bounded grouped requests with independent
   requests before changing this behavior.

The two measured local CPU changes are implemented. Chunking, consolidation,
and prefetch remain follow-up experiments and should not be assumed faster
without server-load, correctness, cancellation, memory, and reconnect
measurements.
