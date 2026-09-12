#!/usr/bin/env python3
"""Read NativeHA SQLite sessions without modifying or copying the database."""
import argparse
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path


def read_rows(database, session, *, limit, severity, category, contains, after_id):
    # Identifiers cannot be SQL parameters; accept only an existing log table.
    sessions = [row[0] for row in database.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'log_*' ORDER BY rowid DESC"
    )]
    if not sessions:
        return None, []
    name = session or sessions[0]
    if name not in sessions:
        raise ValueError(f"Unknown session: {name}")
    table = '"' + name.replace('"', '""') + '"'
    clauses, parameters = ["id > ?"], [after_id]
    levels = ["debug", "info", "warning", "error"]
    selected = levels[levels.index(severity):]
    clauses.append("severity IN (" + ",".join("?" for _ in selected) + ")")
    parameters.extend(selected)
    if category:
        clauses.append("category = ?")
        parameters.append(category)
    if contains:
        # BLOB instr also searches beyond embedded NUL characters.
        clauses.append("instr(CAST(message AS BLOB), CAST(? AS BLOB)) > 0")
        parameters.append(contains)
    parameters.append(limit)
    rows = list(database.execute(
        f"SELECT id, timestamp, severity, category, file, function, line, message FROM {table} "
        + "WHERE " + " AND ".join(clauses) + " ORDER BY id DESC LIMIT ?", parameters
    ))
    return name, list(reversed(rows))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=Path.home() / "Library/Caches/NativeHA_Logs.sqlite")
    parser.add_argument("--sessions", action="store_true", help="list newest session tables (no row scans)")
    parser.add_argument("--session", help="exact table name; defaults to the most recently created session")
    parser.add_argument("--limit", type=int, default=100, help="maximum rows or session names (default 100)")
    parser.add_argument("--severity", choices=["debug", "info", "warning", "error"], default="warning", help="minimum severity (default warning)")
    parser.add_argument("--category")
    parser.add_argument("--contains", help="literal substring in the complete message")
    parser.add_argument("--after-id", type=int, default=0)
    parser.add_argument("--json", action="store_true", help="newline-delimited JSON with complete messages")
    args = parser.parse_args()
    if args.limit < 1 or args.after_id < 0:
        parser.error("--limit must be positive and --after-id nonnegative")
    try:
        uri = args.database.expanduser().resolve().as_uri() + "?mode=ro"
        with sqlite3.connect(uri, uri=True, timeout=1) as database:
            database.row_factory = sqlite3.Row
            if args.sessions:
                for row in database.execute(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'log_*' ORDER BY rowid DESC LIMIT ?",
                    (args.limit,),
                ):
                    print(json.dumps({"session": row[0]}) if args.json else row[0])
                return
            session, rows = read_rows(database, args.session, limit=args.limit,
                                      severity=args.severity, category=args.category,
                                      contains=args.contains, after_id=args.after_id)
            for row in rows:
                entry = {"session": session, **dict(row)}
                if args.json:
                    print(json.dumps(entry, ensure_ascii=False))
                else:
                    timestamp = datetime.fromtimestamp(row["timestamp"], timezone.utc).isoformat(timespec="milliseconds")
                    print(f"{timestamp} #{row['id']} {row['severity']} {row['category']} "
                          f"{row['file']}:{row['line']} {row['function']}\n{row['message']}")
    except (sqlite3.Error, OSError, ValueError) as error:
        parser.exit(1, f"Unable to read NativeHA logs: {error}\n")


if __name__ == "__main__":
    main()
