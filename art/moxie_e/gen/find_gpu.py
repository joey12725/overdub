from huggingface_hub import HfApi
api = HfApi(); seen = {}
qs = ['3d','3D','mesh','Hunyuan','TRELLIS','Trellis','image-to-3d','InstantMesh','TripoSR','TripoSG','CRM','LGM','Unique3D','Wonder3D','Era3D','Zero123','SF3D','stable-fast-3d','Hi3D','Step1X','PartCrafter','CraftsMan','MeshAnything','Michelangelo','SPAR3D','point','gaussian','avatar','character','rig','UniRig','Puppeteer','MagicArticulate','texture','multiview','mv','glb','obj','LHM','human','anime','CharacterGen','StdGEN','PIFu','ECON','SiTH','PSHuman','Cube3D','cube','Roblox','Tripo','Rodin','Meshy','Hyper3D','UltraShape','Hunyuan3D-Omni','Hunyuan3D-3','Lyra','WorldMirror','TexGen','Paint3D','MV-Adapter','mvadapter','retopo','quad']
for q in qs:
    try:
        for s in api.list_spaces(search=q, limit=300, expand=['runtime','likes','sdk']):
            seen[s.id] = s
    except Exception as e:
        print('ERR', q, str(e)[:80])
rows = []
for i, s in seen.items():
    rt = getattr(s, 'runtime', None); hw = getattr(rt, 'hardware', None) if rt else None; st = getattr(rt, 'stage', None) if rt else None
    if st == 'RUNNING' and hw and 'cpu' not in str(hw) and 'zero' not in str(hw):
        rows.append((s.likes or 0, i, hw, s.sdk))
rows.sort(reverse=True)
import collections; print(len(seen), collections.Counter((str(getattr(getattr(s,"runtime",None),"hardware",None)), str(getattr(getattr(s,"runtime",None),"stage",None))) for s in seen.values()).most_common(30))
for r in rows[:120]: print(r)
import re
kw = re.compile(r'3d|mesh|hunyuan|trellis|tripo|instantmesh|sf3d|unique|wonder|crm|lgm|rig|craftsman|step1x|hi3d|spar', re.I)
cand = [i for i, s in seen.items() if getattr(getattr(s,'runtime',None),'stage',None) == 'RUNNING' and getattr(getattr(s,'runtime',None),'hardware',None) is None and kw.search(i)]
cand.sort(key=lambda i: -(seen[i].likes or 0))
print('candidates', len(cand))
out = []
for i in cand[:260]:
    try:
        info = api.space_info(i)
        hw = getattr(info.runtime, 'hardware', None)
        if hw and 'cpu' not in str(hw) and 'zero' not in str(hw):
            print((info.likes, i, hw, info.sdk), flush=True)
    except Exception as e:
        pass
