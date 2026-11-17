"""Print the VRM licence metadata + mesh/material summary of a .vrm (glb) file."""
import sys, json, struct
for p in sys.argv[1:]:
    with open(p,'rb') as f:
        magic,ver,length=struct.unpack('<4sII',f.read(12))
        clen,ctype=struct.unpack('<II',f.read(8))
        j=json.loads(f.read(clen))
    ext=j.get('extensions',{})
    print('=====',p,list(ext.keys()))
    v=ext.get('VRM') or ext.get('VRMC_vrm')
    print(json.dumps(v.get('meta'),indent=1,ensure_ascii=False))
    print('exporter',v.get('exporterVersion'), 'gen', j['asset'])
    for m in j['meshes']:
        print(' mesh',m['name'],[ (j['materials'][pr['material']]['name'], j['accessors'][pr['indices']]['count']//3, len(pr.get('targets',[]))) for pr in m['primitives']])
    print(' nodes',len(j['nodes']),'images',[(i.get('name')) for i in j['images']])
