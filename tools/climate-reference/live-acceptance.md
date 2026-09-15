# Bounded live climate acceptance

`Tests/NativeHAMacTests/ClimateLiveAcceptanceTests.swift` exercises the production Swift climate controller, service builder, `DashboardViewModel`, service controller and REST transport. A real WebSocket connection feeds the production `HAEntitySubscriptionCoordinator`; each service must produce an authoritative entity replacement that agrees with an independent REST GET and the controller's temperature draft.

This harness invokes controller methods, not native UI events or an interactive app launch. Hosted UI interaction and paired visual tests provide separate evidence. Home Assistant state does not establish physical compressor operation.

## Authorization and commands

The default suite skips this test before reading credentials or connecting. Both environment variables below must match exactly. `READ_ONLY` installs the production connection/subscription without service calls:

```sh
NATIVEHA_CLIMATE_LIVE=READ_ONLY NATIVEHA_CLIMATE_LIVE_ENTITY=climate.room_ac \
  swift test --filter ClimateLiveAcceptanceTests
```

Obtain fresh, explicit user authorization for the bounded temperature, preset and Cool/Off sequence before using `ACTUATE`. A prior successful run, this document, or an environment variable is not authorization for another run.

```sh
NATIVEHA_CLIMATE_LIVE=ACTUATE NATIVEHA_CLIMATE_LIVE_ENTITY=climate.room_ac \
  swift test --filter ClimateLiveAcceptanceTests
```

The harness uses the primary URL and token file in `AppConfig.swift`. It requires Celsius, starting mode `off`, target `22.8`, preset `none`, HVAC modes `[cool, off]`, preset options `[none, sleep, activity]`, bounds `19…28`, and step `0.1`. A changed deployment requires review of the sequence; do not loosen these checks merely to make a run pass. A second GET immediately before mutation must still match the starting mode, target and preset.

The only allowed service target is `climate.room_ac`, using `climate.set_temperature`, `climate.set_preset_mode`, and `climate.set_hvac_mode`. The sequence is:

1. Increase the target by one step with the production button debounce.
2. Select Sleep, Activity, then None while Off.
3. Restore target 22.8 if the preset transition has not already restored it.
4. Select Cool, then Off, exactly once.
5. Verify the original mode, target and preset with a final REST GET.

Each step checks one service call, acknowledgement and authoritative subscription replacement within a bounded wait. There are seven calls, or six if None already restores the target. Preset target changes come from Home Assistant; the native client sends no predicted temperature with a preset request.

## Cleanup and limitations

Success, failure and task cancellation enter an unstructured cleanup task that does not inherit the test task's cancellation. It cancels pending debounce, waits for outstanding service work and retires overdue model tasks before restoration. Restoration commands only differing fields, in order: original HVAC mode, preset, then temperature. Each changed field is verified through bounded REST polling, followed by a final GET. Failures are reported rather than treated as restoration success.

Cleanup cannot survive process termination or guarantee restoration during a network/server outage. Do not terminate an active run to interrupt it; allow cleanup to finish. If cleanup fails, inspect the recorded last state and resolve restoration within the authorized target scope. Do not run concurrent climate mutation owners.

## Recorded acceptance

The authorized run on 2026-09-15 UTC passed in 1.698 seconds. Seven service calls and seven authoritative replacements were confirmed. Sleep reported target 23.6°C, Activity 23°C and None 22.9°C; the explicit temperature restoration returned it to 22.8°C. Cool reported `hvac_action: idle`; Off reported `off`.

- [Raw timestamped JSONL evidence](../../Tests/Fixtures/Climate/live-room-ac-acceptance.jsonl): every service payload, acknowledgement, confirmation GET, draft temperature and final state; no token.
- Harness final GET: `2026-09-15T00:45:15.012Z`, Off / 22.8°C / None.
- Independent verifier GET: `2026-09-15T00:45:39.961Z`, same settings, action Off, `last_updated=2026-09-15T00:45:14.918503+00:00`.

The original settings were already restored when cleanup began, so cleanup issued no additional services. The fallback restoration branch is provided for failure handling; this successful run did not exercise a failure or cancellation during live actuation.
