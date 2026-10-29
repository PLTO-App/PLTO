import bpy, sys, json, os
P = sys.argv[sys.argv.index('--')+1]
plan = json.load(open(f'{P}/models_plan.json')); rep = {}
os.makedirs(f'{P}/assets_opt/models', exist_ok=True)
for mid, cfg in plan.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f'{P}/work_opt/models/{mid}/{mid}.gltf')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    tris = lambda: sum((o.data.calc_loop_triangles() or 0) or len(o.data.loop_triangles) for o in meshes)
    before = 0
    for o in meshes: o.data.calc_loop_triangles(); before += len(o.data.loop_triangles)
    ratio = min(1.0, cfg['target_tris'] / max(1, before))
    if ratio < 0.98:
        for o in meshes:
            bpy.context.view_layer.objects.active = o; o.select_set(True)
            m = o.modifiers.new('dec', 'DECIMATE'); m.decimate_type = 'COLLAPSE'; m.ratio = ratio; m.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier='dec'); o.select_set(False)
    after = 0
    for o in meshes: o.data.calc_loop_triangles(); after += len(o.data.loop_triangles)
    out = f'{P}/assets_opt/models/{mid}.glb'
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='AUTO', export_yup=True, export_animations=False, export_cameras=False, export_lights=False)
    rep[mid] = {'before': before, 'after': after, 'glb_bytes': os.path.getsize(out)}
    print('MODEL', mid, before, '->', after, os.path.getsize(out) // 1024, 'KB')
json.dump(rep, open(f'{P}/models_report.json', 'w'), indent=1)
