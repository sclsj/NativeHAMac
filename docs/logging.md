# Debugging with NativeHA logs

NativeHA records selected diagnostics in `~/Library/Caches/NativeHA_Logs.sqlite`. Each process gets a separate table containing its build hash, dirty/clean status, timestamp, and unique suffix. New table timestamps use UTC; older tables used the local timezone. Creation order, not alphabetic table-name order, identifies the newest session. App runs, test runs, and probes can each create a session.

Use the read-only reader from the repository root:

```sh
python3 tools/read_logs.py --sessions --limit 10
python3 tools/read_logs.py --session log_COPY_THE_SESSION_NAME --severity warning
python3 tools/read_logs.py --category network --contains light.desk --json
python3 tools/read_logs.py --severity debug --limit 200 --json
```

Without `--session`, the reader selects the most recently created log table. The default output is the latest 100 warnings/errors, ordered by entry ID. `--after-id` excludes already-read IDs; `--limit` still selects the newest matching rows, so it is not a lossless streaming cursor. `--database` selects another database. `--json` emits one complete JSON object per entry, escaping embedded newlines and NULs without truncation. Listing sessions reads only the schema; filtering messages may scan the chosen session. It never deletes rows or modifies the main database. Read the live WAL through SQLite; do not copy only the main database file while the app is writing.

`AppConfig.loggingPolicy` controls each subsystem independently in both debug and release builds. WebSocket defaults to `warning`; other categories default to `debug`. Temporarily lower WebSocket to `debug` to record all text frames and base64 binary frames. Request failures, command/subscription rejection, timeouts, overflow, reconnect failure, and typed payload decode errors are recorded at warning/error without enabling routine traffic. REST failures include method, URL, request body, HTTP status, response body, and the original error. Decode diagnostics retain the type, coding path, and offending payload. Lifecycle failures identify the component; weather failures include the entity and forecast type. Ordinary cancellation remains quiet at warning/error.

Every selected entry remains complete. There is no database retention cap or queue admission limit. Normal writes run on a utility queue in WAL/FULL transactions every second or at 256 entries. Temporary write failure retains the batch ahead of newer entries and respects the configured retry interval. SQLite storage failures go directly to stderr with the error code, database path, and session, avoiding recursive logging. Normal termination and ordinary logger release attempt a final synchronous flush.

This is diagnostic logging, not a crash recorder. Abrupt process/machine failure can lose the current memory batch. A persistent disk error can retain an increasing backlog and prevent the final flush; no logger can guarantee SQLite persistence while storage remains unavailable. Existing sessions are kept under the approved lossless policy.

See the [logging review](audits/2026-09-11-logging.md) for changes, regression coverage, and validation limits.
