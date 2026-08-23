import requests
import json
import datetime
import time

TOKEN_PATH = "/Users/jin/Documents/Computer/ha_apikey.txt"
BASE_URL = "http://172.20.200.123:8123"

with open(TOKEN_PATH, 'r') as f:
    token = f.read().strip()

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json",
}

# 1. Find the exact entity ID
print("Fetching states to find entity ID...")
try:
    response = requests.get(f"{BASE_URL}/api/states", headers=headers, timeout=10)
    response.raise_for_status()
    states = response.json()
except requests.exceptions.RequestException as e:
    print(f"Failed to fetch states from {BASE_URL}. Let's try the next one.")
    BASE_URL = "http://192.168.71.18:8123"
    response = requests.get(f"{BASE_URL}/api/states", headers=headers, timeout=10)
    response.raise_for_status()
    states = response.json()

entity_id = "sensor.sps30_pm2_5"
found = False
for state in states:
    if "sps30" in state["entity_id"].lower():
        print(f"Found related entity: {state['entity_id']}")
        if state["entity_id"] == "sensor.sps30_pm2_5":
            found = True

if not found:
    for state in states:
        if "sps30" in state["entity_id"].lower() and "pm" in state["entity_id"].lower():
            entity_id = state["entity_id"]
            break

print(f"Using entity ID: {entity_id}")

# 2. Fetch 14 days of data, day by day
end_time = datetime.datetime.now(datetime.timezone.utc)
start_time = end_time - datetime.timedelta(days=14)

all_timestamps = []

for i in range(14):
    day_start = start_time + datetime.timedelta(days=i)
    day_end = day_start + datetime.timedelta(days=1)
    
    start_str = day_start.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    end_str = day_end.strftime("%Y-%m-%dT%H:%M:%S.000Z")
    
    print(f"[{i+1}/14] Fetching data from {start_str} to {end_str}...")
    
    url = f"{BASE_URL}/api/history/period/{start_str}?filter_entity_id={entity_id}&end_time={end_str}&minimal_response"
    
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    
    if data and len(data) > 0:
        history = data[0]
        for item in history:
            ts = item.get("last_updated") or item.get("last_changed")
            if ts:
                all_timestamps.append(ts)
            
    print(f"Processed {i+1} days. Total points so far: {len(all_timestamps)}")
    time.sleep(0.5)

# 3. Check for duplicates
print("\nChecking for duplicates...")
timestamp_counts = {}
for ts in all_timestamps:
    timestamp_counts[ts] = timestamp_counts.get(ts, 0) + 1

duplicates = {ts: count for ts, count in timestamp_counts.items() if count > 1}

print(f"Total timestamps: {len(all_timestamps)}")
print(f"Total unique timestamps: {len(timestamp_counts)}")
print(f"Total duplicated timestamps (types): {len(duplicates)}")
print(f"Total points involved in duplicates: {sum(duplicates.values())}")

if duplicates:
    print("\nSome duplicate timestamps (up to 10):")
    for ts, count in list(duplicates.items())[:10]:
        print(f"  {ts}: {count} times")
else:
    print("\nNo duplicate timestamps found.")

with open("/Users/jin/Documents/Computer/NativeHA/Benchmarks/HistoryFetch/sps30_timestamp_results.txt", "w") as f:
    f.write(f"Entity: {entity_id}\n")
    f.write(f"Total timestamps: {len(all_timestamps)}\n")
    f.write(f"Total unique timestamps: {len(timestamp_counts)}\n")
    f.write(f"Total duplicated timestamps (types): {len(duplicates)}\n")
    f.write(f"Total points involved in duplicates: {sum(duplicates.values())}\n")
    if duplicates:
        for ts, count in list(duplicates.items())[:10]:
            f.write(f"  {ts}: {count} times\n")

print("\nDone.")
