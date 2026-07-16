# Module 03: AppConfig - Isolate Server Profiles And Personal Overrides

Original Claude module: `3. AppConfig.swift: Remove All Hardcoded Personal Data`.

Priority: high, but not a prerequisite for module 02. This should land before broadening NativeHA beyond the current prototype machine.

## Goal

Move personal/server-specific runtime configuration behind explicit profile and preference boundaries. Keep prototype bootstrapping possible, but stop scattering private entity IDs, base URLs, card placement rules, hidden entities, and climate preset guesses through rendering and view-model logic.

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

## Reference Findings

hass-frontend stores dashboard configuration in Lovelace config and user/session state, not source-code constants:

- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/types.ts:9` models dashboard config as `views`.
- `/Users/jin/Documents/HA/hass-frontend/src/data/lovelace/config/view.ts:55` models view-level settings such as `title`, `path`, `icon`, `theme`, `visible`, `subview`, and layout metadata.
- `/Users/jin/Documents/HA/hass-frontend/src/panels/lovelace/hui-root.ts:462` applies Lovelace view visibility per user.

## Target Architecture

Split current `AppConfig` into three categories:

1. Build defaults
   - Nonpersonal constants such as default timeouts, coalescing delays, chart render delays, and fallback layout dimensions.
   - These can remain in source as `NativeHADefaults`.

2. Server profile
   - Base URL candidates.
   - Token source or account reference.
   - Last successful base URL.
   - Server identity metadata from `/api/config`, such as location name, time zone, unit system, and components.
   - Stored in user defaults, app support JSON, or Keychain-backed profile data.

3. User dashboard preferences/overrides
   - Hidden entity IDs.
   - Optional extra card entities.
   - Optional column placement rules.
   - Optional entity-specific UI hints, such as preset display labels.
   - These should be clearly optional local overrides, not part of Lovelace decoding.

Credentials:

- Long-lived tokens must not be printed.
- Prefer Keychain for stored token material.
- If keeping a token-file bootstrap path, make it a debug-only default or an editable profile setting.

## Detailed Implementation Tasks

1. Introduce profile models.
   - `HomeAssistantServerProfile`: id, displayName, baseURLs, tokenReference, lastWorkingBaseURL, created/updated timestamps.
   - `DashboardPreferences`: hiddenEntityIDs, extraEntitiesByCardKey, columnRules, showEntityIDsByDefault.
   - `EntityUIPreferences`: optional per-entity local presentation hints.

2. Create a profile store.
   - Minimal first pass: JSON file in Application Support plus token-file fallback.
   - Better pass: Keychain token storage with profile metadata in Application Support.
   - Include migration from current `AppConfig` constants for the current user only if needed.

3. Refactor `DashboardViewModel.firstWorkingConnection`.
   - Read URL candidates from active profile.
   - Try `lastWorkingBaseURL` first.
   - Persist the successful URL back into the profile.
   - Surface connection status without leaking token paths or token values.

4. Move card cleanup/augmentation out of generic Lovelace transformation.
   - Personal hidden entities and extra entities should be applied in a named `DashboardPreferencesApplier`.
   - Do not mutate decoded `LovelaceCard` values to smuggle in personal overrides.
   - Use stable card identity from module 04 rather than card title strings where possible.

5. Remove `climatePresetTargetTemperatures` from generic climate behavior.
   - If local prediction remains useful, store it as optional entity UI preference.
   - Module 10 should work correctly without local prediction.

6. Clean up benchmark/probe configuration.
   - `HAProbe` already uses `HA_BASE_URL` and `HA_TOKEN`; keep that pattern.
   - Move `GraphBench` and `GraphPyramidBench` to environment variables or shared debug profile loading.

7. Add a small preferences UI only if required.
   - For this module's acceptance, a file-backed active profile is enough.
   - A later UX module can add profile editing.

## File Ownership And Scope

Likely files to edit in future implementation:

- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/AppConfig.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardViewModel.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/ProfileStore.swift`
- Optional new `/Users/jin/Documents/Computer/NativeHA/Sources/NativeHAMac/DashboardPreferences.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/GraphBench/GraphBench.swift`
- `/Users/jin/Documents/Computer/NativeHA/Sources/GraphPyramidBench/GraphPyramidBench.swift`

Out of scope:

- OAuth/native app registration.
- Multi-user HA account management.
- Full settings screen design, unless a future user request asks for it.

## Tests And Verification

Use isolated temporary directories and fake connection probes throughout. The default suite must not read the developer's real token file, touch the real Application Support/Keychain entries, or contact any configured URL.

### Unit tests

Add `Tests/NativeHAMacTests/ProfileStoreTests.swift` and `DashboardPreferencesTests.swift` (the profile types currently belong to the macOS app target, so `NativeHAMacTests` is the existing appropriate target unless implementation moves pure models into `NativeHACore`). Cover:

- An empty temporary store yields documented nonpersonal defaults; valid profile metadata round-trips exactly; malformed, truncated, old-version, absent, and unknown-field files have an explicit recovery/migration result rather than silently selecting a different server.
- Profile selection precedence is deterministic: explicit test override, persisted active profile, then documented debug bootstrap/default. `lastWorkingBaseURL` is tried first only within the active profile, a successful fallback is persisted, and failures cannot mutate another profile.
- Switching profiles cancels the prior connection attempt before starting the new one. A late fake response from the old profile cannot replace the active profile or its server metadata.
- Token material is represented by a reference, not serialized into profile JSON or `UserDefaults`. Token-file bootstrap and Keychain/token-provider failures produce redacted errors.
- Dashboard preferences apply hidden entities, extra entities, column rules, and `showEntityIDsByDefault` only for the selected preference set. Disabling preferences restores the untouched decoded Lovelace model; keys use stable module-04 identity rather than localized title alone.
- Climate and fan presentation remains correct when all entity-specific preset hints are absent.

Add a test log sink and a recursive inspection of emitted diagnostics, saved profile JSON, and any failure attachment names. Seed it with a conspicuous fake token and token-file path and assert neither appears. Do not print file contents on assertion failure until they have been redacted.

### Integration tests

In `Tests/NativeHAMacTests/ProfileConnectionSelectionTests.swift`, inject a fake profile store, token provider, and URL probe into the startup path. Verify first launch, remembered fallback, profile switch, failure, cancellation, and relaunch precedence without network access. Assert profile A's token reference, last URL, preferences, and server metadata never leak into profile B.

These tests should also pass a representative module-04 dashboard through `DashboardPreferencesApplier` and assert the original decoded value remains unchanged. This is a semantic model assertion; a screenshot cannot prove profile isolation.

### GUI rendering, animation, and interaction

No direct GUI snapshot or animation test is required, and the default tests should not produce PNGs or visual baselines. This module explicitly accepts a file-backed active profile and does not include a profile/settings UI. Connection/error-state rendering remains module 05's responsibility. If implementation scope later adds a visible profile picker or changes a connection banner, add only those owned states to `NativeHAMacTests` using the macOS 12 offscreen AppKit procedure in [`../visual-testing.md`](../visual-testing.md); do not snapshot unrelated cards.

### Performance and lifecycle

Add `Tests/NativeHAMacTests/ProfileStorePerformanceTests.swift` with fixed temporary fixtures prepared before measurement:

- Measure cold startup loading/decoding of a store containing 100 profiles separately from warm lookup of the active profile and token reference.
- Measure 1,000 in-memory profile switches with a fake token provider/connection probe, consuming the final selected profile and URL. Also measure preference application to a predecoded 500-card dashboard separately from profile-file decoding.
- Repeatedly switch profiles while a fake connection attempt is suspended, then release stale attempts and assert cancellation leaves no retained tasks, callbacks, or cross-profile mutation. Use memory measurements and explicit weak/lifecycle assertions where possible.

Use the macOS-12-compatible `XCTClockMetric`, `XCTCPUMetric`, and `XCTMemoryMetric`, warm caches before warm-path measurements, and prefer stored XCTest baselines over tight millisecond thresholds. Signposts are useful only if startup/profile switching has meaningful instrumentation. `XCTHitchMetric` is unavailable in Xcode 13.4.1; true app-launch/UI hitch work belongs to a later XCUITest target under newer Xcode, not this module.

### Manual QA

- Start the app using the current active server profile, then verify a failed first URL falls back and the winner is remembered after relaunch.
- Disable personal dashboard preferences and verify the original Lovelace entities return; switch profiles and verify URL choices and overrides remain isolated.
- Inspect console output, error banners, generated test artifacts, and persisted profile metadata for the conspicuous test secret and real credentials. Manual inspection is a final defense; automated redaction tests remain required.

## Risks

- Moving config too early without a migration path can make the prototype harder to run.
- Applying hidden entities at decode time can permanently distort Lovelace models in memory. Keep preferences as a separate presentation layer.
- Token storage changes can accidentally print or persist secrets in plain text. Keep token handling narrow and auditable.
- Tests that use the developer's real home directory or Keychain can overwrite a working profile and make results order-dependent. Require injected storage roots and token providers.
- Asynchronous profile switches can accept a late connection result from the previous profile. Cancellation and cross-profile isolation need deterministic suspended-probe tests.
- Performance fixtures containing realistic-looking tokens can leak through XCTest attachments or failure diagnostics. Use conspicuous synthetic secrets and redaction-safe assertions only.

## Acceptance Criteria

- Source-level personal values are limited to nonshipping debug defaults or removed entirely.
- Runtime server selection comes from an active profile.
- Dashboard personal overrides are isolated in a preference model and can be disabled.
- Climate/fan/card rendering no longer depends on `AppConfig` personal entity IDs for correctness.
- Existing live server can still be reached with the user's current setup.
- Persistence, migration/recovery, selection precedence, remembered fallback, profile switching, and cancellation pass against isolated temporary storage and fake probes with no network access.
- Automated scans prove that profile files, logs, errors, and test artifacts contain neither token values nor sensitive token-file paths.
- Cold profile loading, warm lookup/switching, and 500-card preference application have wall-clock, CPU, and memory baselines; repeated switching leaves no stale tasks or cross-profile updates.
- No direct GUI baseline is required because a settings/profile UI is out of scope; any visible connection-state coverage is owned by module 05.
