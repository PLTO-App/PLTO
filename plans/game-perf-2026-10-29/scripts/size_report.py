import sys,glob,re,os,json
G=sys.argv[1]; out={}
for f in glob.glob(G+'/**/*.import',recursive=True):
    if '/.godot/' in f: continue
    t=open(f).read(); m=re.search(r'source_file="res://([^"]+)"',t)
    if not m: continue
    src=m.group(1); top=src.split('/')[0]
    d=re.findall(r'dest_files=\[(.*?)\]',t); files=re.findall(r'res://([^"]+)',d[0] if d else '')
    kind='tex' if 'importer="texture"' in t else ('scene' if 'importer="scene"' in t else 'other')
    b={'etc2':0,'s3tc':0,'other':0}
    for p in files:
        fp=os.path.join(G,p)
        if not os.path.exists(fp): continue
        s=os.path.getsize(fp)
        if '.etc2.' in p or '.astc.' in p: b['etc2']+=s
        elif '.s3tc.' in p or '.bptc.' in p: b['s3tc']+=s
        else: b['other']+=s
    o=out.setdefault(top,{}).setdefault(kind,{'etc2_astc':0,'s3tc_bptc':0,'other':0,'src_bytes':0,'files':0})
    o['etc2_astc']+=b['etc2']; o['s3tc_bptc']+=b['s3tc']; o['other']+=b['other']; o['files']+=1
    sp=os.path.join(G,src); o['src_bytes']+=os.path.getsize(sp) if os.path.exists(sp) else 0
for top,v in out.items():
    for k,o in v.items(): print(top,k,'files',o['files'],'source',round(o['src_bytes']/1e6,2),'MB | etc2/astc',round(o['etc2_astc']/1e6,2),'MB | s3tc/bptc',round(o['s3tc_bptc']/1e6,2),'MB | single-file',round(o['other']/1e6,2),'MB')
json.dump(out,open(sys.argv[2],'w'),indent=1)
