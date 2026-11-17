import sys, io, contextlib
from gradio_client import Client
for s in sys.argv[1:]:
    print('=====', s, flush=True)
    try:
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            c = Client(s, verbose=False)
            t = c.view_api(return_format='str')
        print((t or buf.getvalue())[:5000])
    except Exception as e:
        print('FAIL', type(e).__name__, str(e)[:300])
