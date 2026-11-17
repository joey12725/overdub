import sys, traceback
from gradio_client import Client
for s in sys.argv[1:]:
    print('=====', s, flush=True)
    try:
        c = Client(s, verbose=False)
        print(c.view_api(return_format='str')[:6000] if hasattr(c,'view_api') else '')
    except Exception as e:
        print('FAIL', type(e).__name__, str(e)[:300])
