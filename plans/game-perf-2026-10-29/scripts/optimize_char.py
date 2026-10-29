import bpy, sys, json, os
from mathutils import kdtree
src, outdir = sys.argv[sys.argv.index('--')+1:][:2]
VARIANTS = {
 'hero': dict(body=3500, head_pf=1.0, hair=0.55, cloth=0.6, shoes=0.3, eyes=0.3, teeth=0.10, drop=['tongue'], tex={'young_lightskinned_female_diffuse': 1024, 'female_casualsuit01_diffuse': 1024, 'female_casualsuit01_normal': 512, 'ponytail01_diffuse': 512, 'shoes01_diffuse': 256, 'shoes01_normal': 256, 'brown_eye': 256, 'eyebrow010': 256, 'eyelashes03': 256, 'teeth': 128, 'tongue01_diffuse': 64}),
 'npc':  dict(body=0.33, head_pf=1.0, hair=0.4, cloth=0.4, shoes=0.2, eyes=0.15, teeth=0, drop=['tongue', 'teeth'], tex={'young_lightskinned_female_diffuse': 512, 'female_casualsuit01_diffuse': 512, 'female_casualsuit01_normal': 256, 'ponytail01_diffuse': 256, 'shoes01_diffuse': 128, 'shoes01_normal': 128, 'brown_eye': 128, 'eyebrow010': 128, 'eyelashes03': 128, 'teeth': 64, 'tongue01_diffuse': 64}),
}
def tri_count(o): o.data.calc_loop_triangles(); return len(o.data.loop_triangles)
def decimate(o, ratio, protect=None, pf=1.0):
    bpy.context.view_layer.objects.active = o; bpy.ops.object.select_all(action='DESELECT'); o.select_set(True)
    me = o.data; keys = me.shape_keys.key_blocks if me.shape_keys else []
    basis = [v.co.copy() for v in me.vertices]; deltas = {}
    for k in keys:
        if k.name != 'Basis': deltas[k.name] = [k.data[i].co - basis[i] for i in range(len(basis))]
    if keys: o.shape_key_clear()
    m = o.modifiers.new('dec', 'DECIMATE'); m.decimate_type = 'COLLAPSE'; m.ratio = ratio; m.use_collapse_triangulate = True
    if protect and protect in o.vertex_groups:
        # inverted group = head vertices are kept; ratio is chosen so head stays full and the body gets `ratio * total` extra tris
        me.calc_loop_triangles(); tot = len(me.loop_triangles); head = sum(1 for t in me.loop_triangles if sum(me.vertices[i].co.z for i in t.vertices) / 3 > 1.3)
        m.ratio = min(1.0, (head + ratio) / tot); m.vertex_group = protect; m.vertex_group_factor = pf; m.invert_vertex_group = True
    bpy.ops.object.modifier_move_to_index(modifier='dec', index=0); bpy.ops.object.modifier_apply(modifier='dec')
    if deltas:
        kd = kdtree.KDTree(len(basis))
        for i, c in enumerate(basis): kd.insert(c, i)
        kd.balance(); idx = [kd.find(v.co)[1] for v in o.data.vertices]
        o.shape_key_add(name='Basis', from_mix=False)
        for name, d in deltas.items():
            sk = o.shape_key_add(name=name, from_mix=False)
            for i, v in enumerate(o.data.vertices): sk.data[i].co = v.co + d[idx[i]]
    o.select_set(False)
report = {}
for vname, cfg in VARIANTS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    for o in list(bpy.data.objects):
        if o.name.startswith('Icosphere') or any(d in o.name for d in cfg['drop']): bpy.data.objects.remove(o, do_unlink=True)
    parts = {}
    for o in [o for o in bpy.data.objects if o.type == 'MESH']:
        n = o.name; before = tri_count(o)
        if n == 'Human': ratio, prot = cfg['body'], ('head' if vname == 'hero' else None)
        elif 'ponytail' in n: ratio, prot = cfg['hair'], None
        elif 'casualsuit' in n: ratio, prot = cfg['cloth'], None
        elif 'shoes' in n: ratio, prot = cfg['shoes'], None
        elif 'high-poly' in n: ratio, prot = cfg['eyes'], None
        elif 'teeth' in n: ratio, prot = cfg['teeth'], None
        else: ratio, prot = 1.0, None
        if prot or (0 < ratio < 0.98): decimate(o, ratio, prot, cfg['head_pf'])
        parts[n] = (before, tri_count(o))
    for im in bpy.data.images:
        s = cfg['tex'].get(im.name.split('.')[0])
        if s and im.size[0] > s: im.scale(s, s)
    for mat in bpy.data.materials:   # export proper alpha modes: cut-outs for hair/brows/lashes/eyes, opaque for the rest
        cut = any(k in mat.name.lower() for k in ('hair', 'ponytail', 'eyebrow', 'eyelash', 'high-poly'))
        mat.blend_method = 'CLIP' if cut else 'OPAQUE'
        try: mat.alpha_threshold = 0.5
        except Exception: pass
        mat.use_backface_culling = not cut
    out = f'{outdir}/char_{vname}.glb'
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='AUTO', export_yup=True, export_animations=False, export_morph=True, export_skins=True, export_cameras=False, export_lights=False)
    tot = sum(a for _, a in parts.values())
    report[vname] = {'parts': parts, 'tris': tot, 'bytes': os.path.getsize(out), 'images': {im.name: list(im.size) for im in bpy.data.images}}
    print('CHAR', vname, 'tris', tot, 'KB', os.path.getsize(out) // 1024, parts)
json.dump(report, open(f'{outdir}/char_report.json', 'w'), indent=1)
