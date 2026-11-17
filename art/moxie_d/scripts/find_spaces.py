"""List running GPU Spaces matching search terms, with hardware (ZeroGPU spaces need quota; dedicated ones do not)."""
import sys, json, urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor
ids = {}
for q in sys.argv[1:]:
    u = "https://huggingface.co/api/spaces?" + urllib.parse.urlencode({"search": q, "limit": 40, "sort": "likes", "direction": -1})
    for s in json.load(urllib.request.urlopen(u, timeout=60)): ids[s["id"]] = s.get("likes", 0)
def rt(i):
    try:
        d = json.load(urllib.request.urlopen("https://huggingface.co/api/spaces/" + i, timeout=60)); r = d.get("runtime") or {}
        return i, r.get("stage"), (r.get("hardware") or {}).get("current")
    except Exception as e: return i, "ERR", None
with ThreadPoolExecutor(8) as ex:
    for i, st, hw in ex.map(rt, ids):
        if st == "RUNNING" and hw and "cpu" not in hw: print(hw, ids[i], i)
