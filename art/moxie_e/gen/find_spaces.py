from huggingface_hub import HfApi
api = HfApi()
seen = {}
for q in ['Hunyuan3D', 'TRELLIS', 'image to 3D', 'TripoSG', 'Tripo', 'Hi3DGen', 'InstantMesh', 'Step1X-3D', 'Direct3D', 'Unique3D', 'PartCrafter', 'CharacterGen', 'StdGEN', 'multiview 3D', 'mesh generation', '3d', 'UniRig', 'rigging', 'Sparc3D', 'Pixal3D', 'SAM 3D']:
    try:
        for s in api.list_spaces(search=q, limit=60, sort='likes', expand=['runtime', 'likes', 'sdk']):
            seen[s.id] = s
    except Exception as e:
        print('ERR', q, e)
rows = []
for i, s in seen.items():
    rt = getattr(s, 'runtime', None)
    hw = getattr(rt, 'hardware', None) if rt else None
    stage = getattr(rt, 'stage', None) if rt else None
    rows.append((s.likes or 0, i, hw, stage, s.sdk))
rows.sort(reverse=True)
for r in rows:
    if r[3] == 'RUNNING' and r[4] == 'gradio':
        print(r)
