# Module 03: AppConfig - Isolate Server Profiles And Personal Overrides

> **Status: intentionally skipped; not complete.** The user decided on
> 2026-08-25 that NativeHA targets one fixed personal Home Assistant deployment.
> Keep the existing fixed server candidates and local token-file bootstrap; do
> not implement profile switching, migration, or a settings UI. The remainder
> of this file is retained as historical planning only and is superseded by
> `docs/user-deviations.md`.

Original Claude module: `3. AppConfig.swift: Remove All Hardcoded Personal Data`.

Priority: high, but not a prerequisite for module 02. This should land before broadening NativeHA beyond the current prototype machine.

## Goal

Separate server-profile state from typed product and presentation policies in `AppConfig.swift`. Keep prototype bootstrapping possible, but stop scattering entity IDs, base URLs, card placement rules, hidden entities, and climate preset guesses through rendering and view-model logic. Keep [`../configurability.md`](../configurability.md) synchronized when an approved configuration surface changes.

## Confirmed Current-Code Findings

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift:6` hardcodes token file path `/Users/jin/Documents/Computer/ha_apikey.txt`.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift:8` hardcodes three Home Assistant base URLs, including the active live URL from the parent audit.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift:28` hardcodes hidden entity IDs.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift:33` injects extra entities into a card by title.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift:39` hardcodes `climate.room_ac` preset target temperatures.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift:46` hardcodes dashboard column placement rules using personal titles and entity IDs.
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift:778` applies these personal overrides while transforming Lovelace cards.
- `/Users/jin/Documents/Computer/NativeHA/Sources/GraphBench/GraphBench.swift` and `/Users/jin/Documents/Computer/NativeHA/Sources/GraphPyramidBench/GraphPyramidBench.swift` also hardcode local token/base URL assumptions.

Confirmed nuance: hardcoded config is acceptable for the prototype, but it must be isolated as profile data. Do not pretend these values are generic Home Assistant behavior.

## Post-Module-01/02/09 Configuration Constraints

The original line hints predate several approved typed policies now present in
`AppConfig.swift`. Module 03 research must inventory and preserve—not collapse
into server-profile storage—the graph time-range, render scheduling,
interaction, tooltip formatting, WebSocket safety, and diagnostic logging
policies recorded in `docs/configurability.md`. Core Graphics is the user's
current primary renderer; Metal remains WIP and profile migration must not
silently change that selection.

Switching profiles is also a generation boundary for the implemented
WebSocket/history/graph owners. A profile change must cancel the old connection,
history feeds, and render coordinators before a late callback can publish or
seed a cache owned by the new profile.

## Reference Findings

hass-frontend stores dashboard configuration in Lovelace config and user/session state, not source-code constants:

- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/types.ts:9` models dashboard config as `views`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/view.ts:55` models view-level settings such as `title`, `path`, `icon`, `theme`, `visible`, `subview`, and layout metadata.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/hui-root.ts:462` applies Lovelace view visibility per user.

## Target Architecture

Separate the current mixed configuration into three categories:

1. Typed `AppConfig` product policies
   - Keep approved ranges, scheduling, layout, interaction, sampling, cache budgets, thresholds, and useful presentation choices in `Sources/NativeHAMac/AppConfig.swift`.
   - Prefer typed policies/enums over unrelated scalar constants.

2. Server profile
   - Base URL candidates.
   - Token source or account reference.
   - Last successful base URL.
   - Server identity metadata from `/api/config`, such as location name, time zone, unit system, and components.
   - Stored in user defaults or app support JSON as appropriate.

3. Local dashboard presentation policies
   - Hidden entity IDs.
   - Optional extra card entities.
   - The approved default-dashboard three-column placement/layout rules.
   - Optional entity-specific UI hints, such as preset display labels.
   - Keep these typed in `AppConfig.swift`, separate from Lovelace decoding and server-profile persistence.

Credentials:

- The existing local token-file bootstrap may remain. Credential migration, redaction, or Keychain work is not required by this module.

## Detailed Implementation Tasks

1. Introduce profile models.
   - `HomeAssistantServerProfile`: id, displayName, baseURLs, tokenReference, lastWorkingBaseURL, created/updated timestamps.
   - `DashboardPresentationPolicy`: typed `AppConfig` values for hidden entities, extra entities, column/layout rules, and entity-ID display.
   - `EntityUIPolicy`: optional typed `AppConfig` presentation hints.

2. Create a profile store.
   - Minimal first pass: JSON file in Application Support plus token-file fallback.
   - Include migration from current `AppConfig` constants for the current user only if needed.

3. Refactor `DashboardViewModel.firstWorkingConnection`.
   - Read URL candidates from active profile.
   - Try `lastWorkingBaseURL` first.
   - Persist the successful URL back into the profile.
   - Surface connection status.

4. Move card cleanup/augmentation out of generic Lovelace transformation.
   - Local hidden entities and extra entities should be applied in a named presentation-policy applier backed by `AppConfig.swift`.
   - Do not mutate decoded `LovelaceCard` values to smuggle in personal overrides.
   - Use stable card identity from module 04 rather than card title strings where possible.

5. Remove `climatePresetTargetTemperatures` from generic climate behavior.
   - If local prediction remains useful, store it as an optional typed `AppConfig` entity UI policy.
   - Module 10 should work correctly without local prediction.

6. Clean up benchmark/probe configuration.
   - `HAProbe` already uses `HA_BASE_URL` and `HA_TOKEN`; keep that pattern.
   - Move `GraphBench` and `GraphPyramidBench` to environment variables or shared debug profile loading.

7. Do not add a settings UI for these configuration surfaces unless a later task explicitly requests one.

## File Ownership And Scope

Likely files to edit in future implementation:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/ProfileStore.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardPresentationPolicy.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/GraphBench/GraphBench.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/GraphPyramidBench/GraphPyramidBench.swift`

Out of scope:

- OAuth/native app registration.
- Multi-user HA account management.
- Full settings screen design, unless a future user request asks for it.

## Tests And Verification

Use isolated temporary directories and fake connection probes throughout. The default suite must not modify the developer's real token file or Application Support entries, or contact any configured URL.

### Unit tests

Add `Tests/NativeHAMacTests/ProfileStoreTests.swift` and `DashboardPresentationPolicyTests.swift` (the types currently belong to the macOS app target, so `NativeHAMacTests` is the existing appropriate target unless implementation moves pure models into `NativeHACore`). Cover:

- An empty temporary store yields documented nonpersonal defaults; valid profile metadata round-trips exactly; malformed, truncated, old-version, absent, and unknown-field files have an explicit recovery/migration result rather than silently selecting a different server.
- Profile selection precedence is deterministic: explicit test override, persisted active profile, then documented debug bootstrap/default. `lastWorkingBaseURL` is tried first only within the active profile, a successful fallback is persisted, and failures cannot mutate another profile.
- Switching profiles cancels the prior connection attempt before starting the new one. A late fake response from the old profile cannot replace the active profile or its server metadata.
- Token-file bootstrap and any profile token reference follow deterministic precedence without changing another profile.
- Typed `AppConfig` presentation policies apply hidden entities, extra entities, the approved default-dashboard column rules, and `showEntityIDsByDefault` without mutating the decoded Lovelace model; keys use stable module-04 identity rather than localized title alone.
- Climate and fan presentation remains correct when all entity-specific preset hints are absent.

### Integration tests

In `Tests/NativeHAMacTests/ProfileConnectionSelectionTests.swift`, inject a fake profile store, token provider, and URL probe into the startup path. Verify first launch, remembered fallback, profile switch, failure, cancellation, and relaunch precedence without network access. Assert profile A's token reference, last URL, and server metadata never leak into profile B.

These tests should also pass a representative module-04 dashboard through the `AppConfig`-backed presentation-policy applier and assert the original decoded value remains unchanged. This is a semantic model assertion; a screenshot cannot prove configuration isolation.

### GUI rendering, animation, and interaction

No direct GUI snapshot or animation test is required, and the default tests should not produce PNGs or visual baselines. This module explicitly accepts a file-backed active profile and does not include a profile/settings UI. Connection/error-state rendering remains module 05's responsibility. If implementation scope later adds a visible profile picker or changes a connection banner, add only those owned states to `NativeHAMacTests` using the macOS 12 offscreen AppKit procedure in [`../visual-testing.md`](../visual-testing.md); do not snapshot unrelated cards.

### Performance and lifecycle

Add `Tests/NativeHAMacTests/ProfileStorePerformanceTests.swift` with fixed temporary fixtures prepared before measurement:

- Measure cold startup loading/decoding of a store containing 100 profiles separately from warm lookup of the active profile and token reference.
- Measure 1,000 in-memory profile switches with a fake token provider/connection probe, consuming the final selected profile and URL. Also measure presentation-policy application to a predecoded 500-card dashboard separately from profile-file decoding.
- Repeatedly switch profiles while a fake connection attempt is suspended, then release stale attempts and assert cancellation leaves no retained tasks, callbacks, or cross-profile mutation. Use memory measurements and explicit weak/lifecycle assertions where possible.

Use the macOS-12-compatible `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, warm caches before warm-path measurements, and prefer stored XCTest baselines over tight millisecond thresholds. Signposts are useful only if startup/profile switching has meaningful instrumentation. `XCTHitchMetric` is unavailable in Xcode 13.4.1; true app-launch/UI hitch work belongs to a later XCUITest target under newer Xcode, not this module.

### Manual QA

- Start the app using the current active server profile, then verify a failed first URL falls back and the winner is remembered after relaunch.
- Disable the local dashboard presentation policy and verify the original Lovelace entities return; switch profiles and verify server URL choices remain isolated.
- Confirm the configured local token bootstrap and active profile still connect as expected.

## Risks

- Moving config too early without a migration path can make the prototype harder to run.
- Applying hidden entities at decode time can permanently distort Lovelace models in memory. Keep the `AppConfig` policy as a separate presentation layer.
- Tests that use the developer's real home directory or profile files can overwrite a working profile and make results order-dependent. Require injected storage roots and token providers.
- Asynchronous profile switches can accept a late connection result from the previous profile. Cancellation and cross-profile isolation need deterministic suspended-probe tests.

## Acceptance Criteria

- Server-profile state and approved typed `AppConfig` product/presentation policies have separate, explicit ownership.
- Runtime server selection comes from an active profile.
- Dashboard presentation overrides are isolated in typed `AppConfig` policies and do not mutate decoded Lovelace data.
- Climate/fan/card rendering no longer depends on `AppConfig` personal entity IDs for correctness.
- Existing live server can still be reached with the user's current setup.
- Persistence, migration/recovery, selection precedence, remembered fallback, profile switching, and cancellation pass against isolated temporary storage and fake probes with no network access.
- Cold profile loading, warm lookup/switching, and 500-card presentation-policy application have wall-clock, CPU, and memory baselines; repeated switching leaves no stale tasks or cross-profile updates.
- No direct GUI baseline is required because a settings/profile UI is out of scope; any visible connection-state coverage is owned by module 05.
