import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ReadLogsTests(unittest.TestCase):
    def test_latest_session_filter_order_and_complete_unicode_message(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "logs.sqlite"
            with sqlite3.connect(path) as database:
                # Creation order, not the git-hash-based table name, selects latest.
                for table in ["log_z_old", "log_a_new"]:
                    database.execute(f"CREATE TABLE {table}(id INTEGER PRIMARY KEY, timestamp REAL, severity TEXT, category TEXT, file TEXT, function TEXT, line INTEGER, message TEXT)")
                for index, level in enumerate(["warning", "info", "error"], 1):
                    database.execute("INSERT INTO log_a_new VALUES (?,0,?,'network','Client.swift','send',12,?)",
                                     (index, level, f"prefix\0温度-{index}"))
            tool = Path(__file__).with_name("read_logs.py")
            base = [sys.executable, str(tool), "--database", str(path)]
            result = subprocess.run(base + ["--json", "--contains", "温度", "--category", "network"], capture_output=True, text=True, check=True)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual([row["id"] for row in rows], [1, 3])
            self.assertEqual(rows[-1]["message"], "prefix\0温度-3")
            self.assertEqual(rows[-1]["session"], "log_a_new")
            limited = subprocess.run(base + ["--json", "--limit", "1"], capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(limited.stdout)["id"], 3)
            rejected = subprocess.run(base + ["--session", 'log_a_new"; DROP TABLE log_a_new;--'], capture_output=True, text=True)
            self.assertEqual(rejected.returncode, 1)
            sessions = subprocess.run(base + ["--sessions"], capture_output=True, text=True, check=True)
            self.assertEqual(sessions.stdout.splitlines(), ["log_a_new", "log_z_old"])


if __name__ == "__main__":
    unittest.main()
