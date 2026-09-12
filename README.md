# NativeHA

Swift-native Home Assistant client prototype focused on faster day-to-day control than a WebView-first app.

The first implementation slice is a reusable Swift package:

- `NativeHACore`: Home Assistant models and a small authenticated REST client.
- `ha-probe`: command-line connectivity probe for a local Home Assistant instance.
- `NativeHACoreTests`: request construction and decoding tests.
- `NativeHAMac`: native macOS dashboard app.
- `GraphBench`: graph algorithm/rendering benchmark using real Home Assistant history.
- `NativeHAMacTests`: graph contracts, offscreen GUI PNG checks, animation keyframes, and XCTest performance metrics that run on macOS 12.

The current app is macOS-only and intentionally avoids WebView/JavaScript. It reads the Lovelace dashboard config through Home Assistant's WebSocket API, renders supported cards with SwiftUI, and renders history graphs through off-main CoreGraphics bitmaps with a lightweight SwiftUI hover/gesture overlay.

## Local Environment Notes

- Current machine: Swift 5.6.1, Xcode 13.4.1.
- Official Home Assistant iOS now requires a much newer Xcode than this machine has installed.
- Global Git config points HTTP(S) traffic at `127.0.0.1:7897`; that proxy was not reachable during setup. I did not change the global config.

## Build

```sh
cd /Users/jin/Documents/Computer/NativeHA
swift test
```

See [`docs/visual-testing.md`](docs/visual-testing.md) for GUI artifacts, approved visual baselines, animation-frame checks, and performance-test guidance.

## Run The macOS App

```sh
cd /Users/jin/Documents/Computer/NativeHA
swift run NativeHAMac
```

Current hardcoded runtime config is in `Sources/NativeHAMac/AppConfig.swift`:

- Token file: `/Users/jin/Documents/Computer/ha_apikey.txt`
- Primary URL: `http://joyj.me:8123`
- Fallback URLs: `http://172.20.200.123:8123`, `http://192.168.71.18:8123`
- Interactive graph rendering: full screen backing resolution with serialized, latest-request coalescing during gestures.

Supported native Lovelace cards:

- `entities`
- `history-graph`
- `weather-forecast`
- `vertical-stack`
- `markdown`

Supported controls currently include toggles for `switch`, `fan`, `input_boolean`, and `automation` entities.

## Error logs

Debug builds provide logging; release builds compile it out. See [logging and inspection commands](docs/logging.md). To inspect recent warnings/errors without modifying the database:

```sh
python3 tools/read_logs.py --sessions --limit 10
python3 tools/read_logs.py --severity warning --limit 100 --json
```

## Graph Benchmarks

```sh
cd /Users/jin/Documents/Computer/NativeHA
swift run GraphBench
```

The app graph path now uses:

- Full history fetch from Home Assistant.
- Cached numeric/date parsing so zoom and pan do not reparse raw Home Assistant history.
- Binary visible-range slicing so interaction cost scales with pixels drawn, not total history size.
- Fidelity-preserving min/max downsampling for both active interaction and the settled frame.
- One in-flight viewport bitmap plus one overwriteable latest request, so continuous gestures publish at render throughput without obsolete render storms or a 100% stale-token discard rate.
- Nice tick calculation per unit group, with fixed 0/1 scaling for binary state graphs.
- Off-main CoreGraphics rendering to `CGImage`.
- SwiftUI display of the rendered bitmap plus cheap axis labels, hover tooltip, pinch zoom, and trackpad panning.

## Probe A Home Assistant Instance

Use a long-lived access token or another temporary token you are comfortable using for local testing:

```sh
cd /Users/jin/Documents/Computer/NativeHA
HA_BASE_URL=http://homeassistant.local:8123 HA_TOKEN=<token> swift run ha-probe
```

The probe intentionally reads from environment variables rather than local secret files.

## Direction

The performance-focused app architecture should be:

- Native SwiftUI surfaces for common controls and status scanning.
- WebSocket subscriptions for live entity updates.
- REST calls for setup, config, service calls, and low-frequency operations.
- Local cache keyed by `entity_id` so lists and dashboards do not wait on full reloads.
- No authenticated WebView for this app direction; unsupported Lovelace cards should receive native renderers over time.
