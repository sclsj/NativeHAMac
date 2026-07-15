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

Unit tests:

- Profile store loads defaults when no file exists.
- Profile store saves and reloads base URL candidates without token values in logs.
- `firstWorkingConnection` tries last successful URL first.
- Hidden entity preferences are applied only when preferences are enabled.
- Extra card entities are keyed by stable card identity or explicit preference key, not localized/card title text alone.
- Climate detail works without `climatePresetTargetTemperatures`.

Manual QA:

- App starts using the current active server profile.
- A failed first URL falls back to another profile URL and remembers the winner.
- Removing hidden-entity preferences shows the original Lovelace entities again.
- No credentials appear in console output, error banners, or generated docs.

## Risks

- Moving config too early without a migration path can make the prototype harder to run.
- Applying hidden entities at decode time can permanently distort Lovelace models in memory. Keep preferences as a separate presentation layer.
- Token storage changes can accidentally print or persist secrets in plain text. Keep token handling narrow and auditable.

## Acceptance Criteria

- Source-level personal values are limited to nonshipping debug defaults or removed entirely.
- Runtime server selection comes from an active profile.
- Dashboard personal overrides are isolated in a preference model and can be disabled.
- Climate/fan/card rendering no longer depends on `AppConfig` personal entity IDs for correctness.
- Existing live server can still be reached with the user's current setup.

