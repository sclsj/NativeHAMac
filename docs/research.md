# Home Assistant Native App Research

> Historical scaffold research, not a current implementation plan. Product
> decisions in `docs/user-deviations.md` supersede the open questions below;
> use that file and the rescue-plan index for current direction.

Date: 2026-07-03

## Official Sources Reviewed

- Home Assistant native app integration: https://developers.home-assistant.io/docs/api/native-app-integration/
- Connecting and registering a native app: https://developers.home-assistant.io/docs/api/native-app-integration/setup/
- Sending data home via mobile app webhooks: https://developers.home-assistant.io/docs/api/native-app-integration/sending-data/
- REST API: https://developers.home-assistant.io/docs/api/rest/
- WebSocket API: https://developers.home-assistant.io/docs/api/websocket/
- Authentication API: https://developers.home-assistant.io/docs/auth_api/
- Official Apple app repository: https://github.com/home-assistant/iOS
- Official Swift SDK (`HAKit`): https://github.com/home-assistant/HAKit

## Research Summary

Home Assistant supports a first-class native app path. The official guide covers connecting to an instance, device registration, sending device/location data, service calls, events, templates, and an authenticated WebView fallback.

Authentication uses OAuth 2 with IndieAuth. Native apps need a client ID represented by a website and an approved redirect URI. Home Assistant scans the first 10 KB of that client ID page for `rel="redirect_uri"` links, so a custom app scheme such as `nativeha://auth` needs a small public client page before production login is polished.

Local discovery should use Bonjour/Zeroconf for `_home-assistant._tcp.local.` when available. Otherwise, the app should let the user enter an instance URL.

The WebSocket API lives at `/api/websocket`. The client connects, receives `auth_required`, sends an `auth` message with an access token, receives `auth_ok`, then sends commands with unique integer IDs. This is the right foundation for fast state updates because the app can subscribe once and incrementally update a local cache.

The REST API lives under `/api/` on the same host and requires `Authorization: Bearer TOKEN`. It is useful for low-frequency setup work such as `/api/config`, full `/api/states` bootstrap fetches, and service calls such as `/api/services/<domain>/<service>`.

The native `mobile_app` integration can register devices by POSTing to `/api/mobile_app/registrations`. Registration returns a `webhook_id`, and may also return `cloudhook_url`, `remote_ui_url`, and an encryption secret. Webhook traffic should prefer cloudhook, then remote UI, then the locally constructed webhook URL.

Home Assistant's official Apple app is Swift-based and uses the Home Assistant Swift SDK (`HAKit`) for REST and WebSocket communication. Its current README says it needs a much newer Xcode than the one installed locally, so this scaffold starts with a small self-contained Swift package and keeps `HAKit` as the preferred integration dependency for the real app target.

## Performance Hypothesis

The main performance win should come from avoiding WebView navigation and frontend rendering for common tasks:

- Keep a normalized in-memory entity cache fed by WebSocket updates.
- Render high-use domains natively first: lights, switches, climate, covers, locks, media players, sensors, scenes, scripts, and automations.
- Use optimistic service calls for fast controls, then reconcile with server state updates.
- Persist the last good entity snapshot for instant cold-start UI.
- Use native list diffing and domain-specific controls instead of rendering Lovelace cards in a WebView.
- Load media/camera entities lazily and use native media components where possible.

## Open Product Questions

- Should the first app target be iPhone only, universal iPhone/iPad, macOS, or all Apple platforms?
- Should the app be a complete replacement UI, or a fast control surface with WebView fallback for complex Lovelace dashboards?
- Which Home Assistant domains should be first-class in the MVP?
- Should login start with long-lived token entry for speed, then OAuth later, or should OAuth be implemented first?
- Should we integrate with `mobile_app` sensors, location, notifications, widgets, Shortcuts, and Apple Watch in the first phase or later?
