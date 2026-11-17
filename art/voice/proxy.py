"""CLI proxy client for the voice pipeline (same tunnel + key file as tools/img).

The proxy listens only on the server, so an SSH tunnel is opened on demand. The API key is read
from a private file and is never printed, logged or copied.
"""
import http.client, json, os, subprocess, time, urllib.request, urllib.error

KEYFILE = os.environ.get("OD_IMG_KEYFILE", r"C:\Users\joeya\.t3\userdata\secrets\files\f3b399dfc713106618d4f5d4f9c445cb")
PORT = 18317
BASE = "http://127.0.0.1:%d/v1" % PORT


def _up():
    # The proxy is shared and can take 10-20 s to answer, so only test that the port accepts.
    import socket
    try:
        socket.create_connection(("127.0.0.1", PORT), timeout=3).close()
        return True
    except Exception:
        return False


def tunnel():
    if _up():
        return
    key = os.path.expanduser("~/.ssh/id_ed25519")
    subprocess.run(["ssh", "-i", key, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
                    "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30", "-f", "-N",
                    "-L", "%d:127.0.0.1:8317" % PORT, "root@your-server.example"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(2)


def _auth():
    with open(KEYFILE, "r") as f:
        return {"Authorization": "Bearer " + f.read().strip()}


def request(path, body=None, headers=None, timeout=300, method=None, tries=4):
    """Returns (status, content_type, bytes). body: dict (JSON) | bytes | None.
    The shared tunnel drops connections under load, so transport errors are retried."""
    last = None
    for i in range(tries):
        try:
            return _request(path, body, headers, timeout, method)
        except (urllib.error.URLError, http.client.HTTPException, ConnectionError, TimeoutError, OSError) as e:
            last = e
            time.sleep(3 + 4 * i)
    raise last


def _request(path, body=None, headers=None, timeout=300, method=None):
    tunnel()
    h = _auth()
    data = None
    if isinstance(body, (dict, list)):
        data = json.dumps(body).encode("utf-8")
        h["Content-Type"] = "application/json"
    elif body is not None:
        data = body
    if headers:
        h.update(headers)
    req = urllib.request.Request(BASE + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.headers.get("Content-Type", ""), r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", ""), e.read()


def multipart(fields, files):
    """fields: {name: str}; files: {name: (filename, bytes, mime)} -> (body, content_type)."""
    b = "----odvoice%d" % int(time.time() * 1000)
    out = []
    for k, v in fields.items():
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (b, k, v)).encode("utf-8"))
    for k, (fn, data, mime) in files.items():
        out.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % (b, k, fn, mime)).encode("utf-8"))
        out.append(data)
        out.append(b"\r\n")
    out.append(("--%s--\r\n" % b).encode("utf-8"))
    return b"".join(out), "multipart/form-data; boundary=" + b


if __name__ == "__main__":
    s, ct, d = request("/models", timeout=180)
    print(s, ct)
    try:
        j = json.loads(d)
        for m in j.get("data", []):
            print(m.get("id"), m.get("owned_by", ""), m.get("type", ""))
    except Exception:
        print(d[:600])
