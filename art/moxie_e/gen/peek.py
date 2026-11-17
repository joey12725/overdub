import sys
from huggingface_hub import HfApi, hf_hub_download
api = HfApi()
for s in sys.argv[1:]:
    try:
        info = api.space_info(s)
        files = [f.rfilename for f in info.siblings]
        print('=====', s, getattr(info.runtime, 'hardware', None), getattr(info.runtime,'stage',None), files[:25])
        if 'app.py' in files:
            p = hf_hub_download(s, 'app.py', repo_type='space')
            t = open(p, encoding='utf8', errors='ignore').read()
            print(len(t)); 
            import re
            for m in re.finditer(r'(https?://[^\s"\')]+|api_name\s*=\s*[^,)]+|spaces\.GPU|Client\([^)]*\))', t):
                print('   ', m.group(0)[:140])
    except Exception as e:
        print('ERR', s, str(e)[:200])
