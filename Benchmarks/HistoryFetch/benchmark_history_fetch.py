#!/usr/bin/env python3
"""Read-only Home Assistant history transport benchmark.

The access token is read from HA_TOKEN or --token-file and is never printed or
written to the results. The benchmark compares equivalent entity lists and
fixed time windows across:

* REST /api/history/period
* finite WebSocket history/history_during_period
* NativeHA's current WebSocket history/stream request shape

Python's JSON decoding is timed separately from socket receive time. This does
not measure Swift decoding, projection, graph preparation, or drawing.
"""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import statistics
import time
from typing import Any
from urllib.error import URLError
from urllib.parse import quote, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen

import websockets


DEFAULT_BASE_URLS = [
    "http://joyj.me:8123",
    "http://172.20.200.123:8123",
    "http://192.168.71.18:8123",
]
DEFAULT_TOKEN_FILE = "/Users/jin/Documents/Computer/ha_apikey.txt"
DEFAULT_ENTITIES = [
    "sensor.sps30_pm4_0",
    "sensor.sps30_pm10",
    "sensor.sps30_pm2_5",
    "sensor.sps30_pm1_0",
]


@dataclass
class Result:
    method: str
    run: int
    hours: int
    entity_count: int
    sample_count: int
    response_bytes: int
    connect_seconds: float
    auth_seconds: float
    server_and_receive_seconds: float
    first_data_seconds: float | None
    json_decode_seconds: float
    total_seconds: float
    message_count: int


def iso(value: datetime) -> str:
    return value.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ws_url(base_url: str) -> str:
    parsed = urlparse(base_url)
    scheme = "wss" if parsed.scheme == "https" else "ws"
    return urlunparse((scheme, parsed.netloc, "/api/websocket", "", "", ""))


def read_token(path: str) -> str:
    token = os.environ.get("HA_TOKEN")
    if token:
        return token.strip()
    return Path(path).read_text(encoding="utf-8").strip()


def select_base_url(base_urls: list[str], token: str) -> str:
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    errors: list[str] = []
    for base_url in base_urls:
        request = Request(f"{base_url}/api/config", headers=headers)
        try:
            with urlopen(request, timeout=10) as response:
                if 200 <= response.status < 300:
                    return base_url
        except (OSError, URLError) as error:
            errors.append(f"{base_url}: {type(error).__name__}")
    raise RuntimeError("No configured Home Assistant URL was reachable: " + ", ".join(errors))


def count_finite_samples(result: dict[str, list[dict[str, Any]]]) -> int:
    return sum(len(states) for states in result.values())


def benchmark_rest(
    *,
    base_url: str,
    token: str,
    entities: list[str],
    start_time: datetime,
    end_time: datetime,
    run: int,
) -> Result:
    begin = time.perf_counter()
    query = urlencode(
        {
            "filter_entity_id": ",".join(entities),
            "end_time": iso(end_time),
            "minimal_response": "",
            "significant_changes_only": "0",
        }
    )
    url = f"{base_url}/api/history/period/{quote(iso(start_time), safe='')}?{query}"
    request = Request(
        url,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )
    receive_start = time.perf_counter()
    with urlopen(request, timeout=180) as response:
        payload = response.read()
    received = time.perf_counter()
    decoded = json.loads(payload)
    decode_done = time.perf_counter()
    samples = sum(len(series) for series in decoded)
    return Result(
        method="rest",
        run=run,
        hours=int((end_time - start_time).total_seconds() / 3600),
        entity_count=len(entities),
        sample_count=samples,
        response_bytes=len(payload),
        connect_seconds=0,
        auth_seconds=0,
        server_and_receive_seconds=received - receive_start,
        first_data_seconds=None,
        json_decode_seconds=decode_done - received,
        total_seconds=decode_done - begin,
        message_count=1,
    )


async def authenticate(websocket: Any, token: str) -> tuple[float, float]:
    connected = time.perf_counter()
    auth_required = json.loads(await websocket.recv())
    if auth_required.get("type") != "auth_required":
        raise RuntimeError(f"Unexpected WebSocket greeting: {auth_required.get('type')}")
    auth_start = time.perf_counter()
    await websocket.send(json.dumps({"type": "auth", "access_token": token}))
    auth_result = json.loads(await websocket.recv())
    if auth_result.get("type") != "auth_ok":
        raise RuntimeError(f"WebSocket authentication failed: {auth_result}")
    return connected, time.perf_counter() - auth_start


async def benchmark_finite_ws(
    *,
    base_url: str,
    token: str,
    entities: list[str],
    start_time: datetime,
    end_time: datetime,
    run: int,
    max_message_bytes: int,
) -> Result:
    begin = time.perf_counter()
    connect_start = begin
    async with websockets.connect(
        ws_url(base_url),
        max_size=max_message_bytes,
        open_timeout=20,
        close_timeout=10,
    ) as websocket:
        connected, auth_seconds = await authenticate(websocket, token)
        request = {
            "id": 1,
            "type": "history/history_during_period",
            "start_time": iso(start_time),
            "end_time": iso(end_time),
            "entity_ids": entities,
            "include_start_time_state": True,
            "minimal_response": True,
            "no_attributes": True,
        }
        await websocket.send(json.dumps(request))
        sent = time.perf_counter()
        message = await websocket.recv()
        received = time.perf_counter()
        decoded = json.loads(message)
        decode_done = time.perf_counter()
        if not decoded.get("success"):
            raise RuntimeError(f"Finite WebSocket request failed: {decoded}")
        result = decoded["result"]
        samples = count_finite_samples(result)
        return Result(
            method="ws_period",
            run=run,
            hours=int((end_time - start_time).total_seconds() / 3600),
            entity_count=len(entities),
            sample_count=samples,
            response_bytes=len(message.encode("utf-8")),
            connect_seconds=connected - connect_start,
            auth_seconds=auth_seconds,
            server_and_receive_seconds=received - sent,
            first_data_seconds=received - sent,
            json_decode_seconds=decode_done - received,
            total_seconds=decode_done - begin,
            message_count=1,
        )


async def benchmark_stream_ws(
    *,
    base_url: str,
    token: str,
    entities: list[str],
    start_time: datetime,
    end_time: datetime,
    run: int,
    max_message_bytes: int,
    capture_frame: str | None,
) -> Result:
    begin = time.perf_counter()
    connect_start = begin
    async with websockets.connect(
        ws_url(base_url),
        max_size=max_message_bytes,
        open_timeout=20,
        close_timeout=10,
    ) as websocket:
        connected, auth_seconds = await authenticate(websocket, token)
        request = {
            "id": 1,
            "type": "history/stream",
            "entity_ids": entities,
            "start_time": iso(start_time),
            "minimal_response": True,
            "significant_changes_only": True,
            "no_attributes": True,
        }
        await websocket.send(json.dumps(request))
        sent = time.perf_counter()
        response_bytes = 0
        decode_seconds = 0.0
        samples = 0
        message_count = 0
        first_data_seconds: float | None = None
        while True:
            message = await websocket.recv()
            received = time.perf_counter()
            response_bytes += len(message.encode("utf-8"))
            decode_start = time.perf_counter()
            decoded = json.loads(message)
            decode_seconds += time.perf_counter() - decode_start
            if decoded.get("type") == "result":
                if not decoded.get("success"):
                    raise RuntimeError(f"History stream subscription failed: {decoded}")
                continue
            if decoded.get("type") != "event":
                continue
            message_count += 1
            states = decoded.get("event", {}).get("states", {})
            chunk_samples = count_finite_samples(states)
            samples += chunk_samples
            if chunk_samples and first_data_seconds is None:
                first_data_seconds = received - sent
                if capture_frame and run == 1:
                    Path(capture_frame).write_text(message, encoding="utf-8")
                finished = time.perf_counter()
                break
        await websocket.send(json.dumps({"id": 2, "type": "unsubscribe_events", "subscription": 1}))
        return Result(
            method="ws_stream",
            run=run,
            hours=int((end_time - start_time).total_seconds() / 3600),
            entity_count=len(entities),
            sample_count=samples,
            response_bytes=response_bytes,
            connect_seconds=connected - connect_start,
            auth_seconds=auth_seconds,
            server_and_receive_seconds=finished - sent - decode_seconds,
            first_data_seconds=first_data_seconds,
            json_decode_seconds=decode_seconds,
            total_seconds=finished - begin,
            message_count=message_count,
        )


def render(result: Result) -> str:
    first = "-" if result.first_data_seconds is None else f"{result.first_data_seconds:.3f}"
    return (
        f"{result.method:9} run={result.run} samples={result.sample_count:8d} "
        f"bytes={result.response_bytes / 1_048_576:7.2f}MiB "
        f"connect={result.connect_seconds:5.3f}s auth={result.auth_seconds:5.3f}s "
        f"wait={result.server_and_receive_seconds:6.3f}s first={first:>6}s "
        f"decode={result.json_decode_seconds:6.3f}s total={result.total_seconds:6.3f}s "
        f"messages={result.message_count}"
    )


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hours", type=int, default=12)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--entities", nargs="+", default=DEFAULT_ENTITIES)
    parser.add_argument("--methods", nargs="+", choices=["rest", "ws_period", "ws_stream"],
                        default=["rest", "ws_period", "ws_stream"])
    parser.add_argument("--base-url", action="append", dest="base_urls")
    parser.add_argument("--token-file", default=DEFAULT_TOKEN_FILE)
    parser.add_argument("--max-message-mib", type=int, default=256)
    parser.add_argument("--output-json")
    parser.add_argument(
        "--capture-stream-frame",
        help="Write the first non-empty stream event for local decode profiling",
    )
    args = parser.parse_args()

    token = read_token(args.token_file)
    base_url = select_base_url(args.base_urls or DEFAULT_BASE_URLS, token)
    end_time = datetime.now(timezone.utc).replace(microsecond=0)
    start_time = end_time - timedelta(hours=args.hours)
    print(f"Home Assistant: {base_url}")
    print(f"Window: {iso(start_time)} to {iso(end_time)}")
    print(f"Entities ({len(args.entities)}): {','.join(args.entities)}")

    results: list[Result] = []
    for run in range(1, args.runs + 1):
        for method in args.methods:
            if method == "rest":
                result = await asyncio.to_thread(
                    benchmark_rest,
                    base_url=base_url,
                    token=token,
                    entities=args.entities,
                    start_time=start_time,
                    end_time=end_time,
                    run=run,
                )
            elif method == "ws_period":
                result = await benchmark_finite_ws(
                    base_url=base_url,
                    token=token,
                    entities=args.entities,
                    start_time=start_time,
                    end_time=end_time,
                    run=run,
                    max_message_bytes=args.max_message_mib * 1_048_576,
                )
            else:
                result = await benchmark_stream_ws(
                    base_url=base_url,
                    token=token,
                    entities=args.entities,
                    start_time=start_time,
                    end_time=end_time,
                    run=run,
                    max_message_bytes=args.max_message_mib * 1_048_576,
                    capture_frame=args.capture_stream_frame,
                )
            results.append(result)
            print(render(result), flush=True)

    print("\nMeans:")
    for method in args.methods:
        selected = [result for result in results if result.method == method]
        print(
            f"{method:9} total={statistics.mean(r.total_seconds for r in selected):.3f}s "
            f"wait={statistics.mean(r.server_and_receive_seconds for r in selected):.3f}s "
            f"decode={statistics.mean(r.json_decode_seconds for r in selected):.3f}s"
        )
    if args.output_json:
        output = {
            "base_url": base_url,
            "start_time": iso(start_time),
            "end_time": iso(end_time),
            "entities": args.entities,
            "results": [asdict(result) for result in results],
        }
        Path(args.output_json).write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    asyncio.run(main())
