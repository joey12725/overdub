"""Resumable multi-connection download of the Hunyuan3D-2mv shape checkpoint (Tencent, see LICENSES.md).
usage: fetch_mv.py <out_dir> [connections]   (env BUDGET_S = seconds to run, default 540; rerun until it prints sha256 ok)"""
import sys, os, json, threading, urllib.request, hashlib, time
BASE = "https://huggingface.co/tencent/Hunyuan3D-2mv/resolve/main/hunyuan3d-dit-v2-mv/"
SIZE = 4928151562; SHA = "d36f5881bcdc56726b73e517cd444c13c60732431622da7268145355c8d38e9c"
d = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 8; CH = 16 << 20
out = os.path.join(d, "model.fp16.safetensors"); cfg = os.path.join(d, "config.yaml")
if not os.path.exists(cfg):
    open(cfg, "wb").write(urllib.request.urlopen(urllib.request.Request(BASE + "config.yaml", headers={"User-Agent": "curl/8"}), timeout=60).read())
state_p = out + ".parts.json"
done = set(json.load(open(state_p))) if os.path.exists(state_p) else set()
if not os.path.exists(out):
    with open(out, "wb") as f: f.truncate(SIZE)
chunks = [i for i in range((SIZE + CH - 1) // CH) if i not in done]
lock = threading.Lock(); deadline = time.time() + float(os.environ.get("BUDGET_S", "540"))
def work(k):
    while time.time() < deadline:
        with lock:
            if not chunks: return
            i = chunks.pop(0)
        a, b = i * CH, min(SIZE, (i + 1) * CH) - 1
        try:
            rq = urllib.request.Request(BASE + "model.fp16.safetensors", headers={"Range": f"bytes={a}-{b}", "User-Agent": "curl/8"})
            data = urllib.request.urlopen(rq, timeout=90).read()
            assert len(data) == b - a + 1
            with lock:
                with open(out, "r+b") as f: f.seek(a); f.write(data)
                done.add(i); json.dump(sorted(done), open(state_p, "w"))
        except Exception as e:
            with lock: chunks.append(i)
ts = [threading.Thread(target=work, args=(k,)) for k in range(N)]
[t.start() for t in ts]; [t.join() for t in ts]
tot = (SIZE + CH - 1) // CH
print(f"{len(done)}/{tot} chunks")
if len(done) == tot:
    h = hashlib.sha256()
    with open(out, "rb") as f:
        for blk in iter(lambda: f.read(1 << 24), b""): h.update(blk)
    print("sha256 ok" if h.hexdigest() == SHA else "SHA MISMATCH " + h.hexdigest())
