"""Resumable multi-connection download of the Hunyuan3D-2 shape checkpoint (same sha256 on Hugging Face and ModelScope).
usage: fetch_model.py <out_path> [connections]"""
import sys, os, json, threading, urllib.request, hashlib, time
URLS = ["https://www.modelscope.cn/models/Tencent-Hunyuan/Hunyuan3D-2/resolve/master/hunyuan3d-dit-v2-0/model.fp16.safetensors",
        "https://huggingface.co/tencent/Hunyuan3D-2/resolve/main/hunyuan3d-dit-v2-0/model.fp16.safetensors"]
SIZE = 4928151562; SHA = "360bc281fc956d4acac0c3d36d5ec0ebf8cdddbf4b8892e894d12419388d479b"
out = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 12; CH = 16 << 20
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
            url = URLS[0] if k % 4 else URLS[1]
            rq = urllib.request.Request(url, headers={"Range": f"bytes={a}-{b}", "User-Agent": "curl/8"})
            data = urllib.request.urlopen(rq, timeout=60).read()
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
