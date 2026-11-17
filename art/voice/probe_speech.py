"""Probe the CLI proxy for any speech capability. Writes art/voice/probe_report.json.
Never prints credentials; only status codes and the first bytes of each response body."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import proxy

out = []
def rec(name, s, ct, d):
    body = d[:300].decode("utf-8", "replace") if not ct.startswith("audio") else "<audio %d bytes>" % len(d)
    out.append({"probe": name, "status": s, "content_type": ct, "body": body})
    print(name, s, ct, body[:200].replace("\n", " "))

s, ct, d = proxy.request("/models", timeout=180)
models = [m["id"] for m in json.loads(d).get("data", [])]
out.append({"models": models})
print("models:", models)

for m in ["gpt-4o-mini-tts", "tts-1", "tts-1-hd", "gpt-audio", "gpt-audio-mini", "gpt-realtime"]:
    try:
        rec("audio/speech " + m, *proxy.request("/audio/speech", {"model": m, "input": "five, six, seven, eight", "voice": "alloy", "response_format": "wav"}, timeout=180))
    except Exception as e:
        rec("audio/speech " + m, -1, "", repr(e).encode())

for m in ["gpt-audio", "gpt-4o-audio-preview", "gpt-6-chat-thinking", "gpt-6-luna"]:
    try:
        rec("chat audio modality " + m, *proxy.request("/chat/completions", {"model": m, "modalities": ["text", "audio"], "audio": {"voice": "alloy", "format": "wav"}, "messages": [{"role": "user", "content": "Say: five, six, seven, eight"}]}, timeout=240))
    except Exception as e:
        rec("chat audio modality " + m, -1, "", repr(e).encode())

# transcription endpoint (tiny silent wav)
import struct
wav = b"RIFF" + struct.pack("<I", 36 + 3200) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16) + b"data" + struct.pack("<I", 3200) + b"\0" * 3200
for m in ["whisper-1", "gpt-4o-transcribe", "gpt-4o-mini-transcribe"]:
    try:
        body, mct = proxy.multipart({"model": m}, {"file": ("a.wav", wav, "audio/wav")})
        rec("audio/transcriptions " + m, *proxy.request("/audio/transcriptions", body, {"Content-Type": mct}, timeout=180))
    except Exception as e:
        rec("audio/transcriptions " + m, -1, "", repr(e).encode())

json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe_report.json"), "w"), indent=1)
