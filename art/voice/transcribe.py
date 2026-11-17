"""Transcribe WAV files through the CLI proxy (/v1/audio/transcriptions).
usage: python -I art/voice/transcribe.py [--model M] [--prompt P] a.wav b.wav ...   (prints JSON)"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import proxy


def transcribe(path, model="gpt-4o-transcribe", prompt=None, timeout=240):
    fields = {"model": model, "language": "en", "response_format": "json"}
    if prompt:
        fields["prompt"] = prompt
    with open(path, "rb") as f:
        body, ct = proxy.multipart(fields, {"file": (os.path.basename(path), f.read(), "audio/wav")})
    s, rct, d = proxy.request("/audio/transcriptions", body, {"Content-Type": ct}, timeout=timeout)
    try:
        return s, json.loads(d).get("text", "")
    except Exception:
        return s, d[:200].decode("utf-8", "replace")


if __name__ == "__main__":
    a = sys.argv[1:]
    model, prompt = "gpt-4o-transcribe", None
    while a and a[0].startswith("--"):
        if a[0] == "--model": model = a[1]
        if a[0] == "--prompt": prompt = a[1]
        a = a[2:]
    for p in a:
        print(json.dumps({"file": os.path.basename(p), "model": model, "result": transcribe(p, model, prompt)}))
