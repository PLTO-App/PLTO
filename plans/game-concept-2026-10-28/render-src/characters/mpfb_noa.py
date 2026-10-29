import bpy, sys, json, math
from bl_ext.user_default.mpfb.services import HumanService
from bl_ext.user_default.mpfb.services.faceservice import FaceService
args = json.loads(sys.argv[sys.argv.index('--')+1])
bpy.ops.wm.read_factory_settings(use_empty=True)
hi = HumanService._create_default_human_info_dict()
hi["phenotype"].update({"gender": 0.0, "age": 0.42, "muscle": 0.45, "weight": 0.48, "height": 0.42, "proportions": 0.65, "cupsize": 0.45,
                        "race": {"asian": 0.1, "caucasian": 0.65, "african": 0.25}})
hi.update({"rig": "game_engine", "eyes": "high-poly.mhclo", "eyebrows": "eyebrow010.mhclo", "eyelashes": "eyelashes03.mhclo",
           "teeth": "teeth_base.mhclo", "tongue": "tongue01.mhclo", "hair": args.get("hair", "ponytail01.mhclo"),
           "clothes": args.get("clothes", ["female_casualsuit02.mhclo", "shoes01.mhclo"]),
           "skin_mhmat": args.get("skin", "young_caucasian_female.mhmat"), "skin_material_type": "MAKESKIN",
           "eyes_material_type": "MAKESKIN", "clothes_material_type": "MAKESKIN"})
st = HumanService.get_default_deserialization_settings(); st["subdiv_levels"] = 0; st["scale"] = 0.1
body = HumanService.deserialize_from_dict(hi, st)
FaceService.set_expression(body, args.get("expr", {}))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
print('BONES', [b.name for b in rig.data.bones][:80])
from mathutils import Vector, Matrix
def aim(bn, target):
    pb = rig.pose.bones.get(bn)
    if pb is None: print('missing', bn); return
    bpy.context.view_layer.update()
    head = pb.matrix.to_translation(); cur = (pb.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = cur.rotation_difference(Vector(target).normalized())
    R = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
    pb.matrix = R @ pb.matrix
    bpy.context.view_layer.update()
print('POSEPOS', rig.data.pose_position, 'hand_l before', rig.pose.bones['hand_l'].head)
for bn, t in args.get("aim", []): aim(bn, t)
print('hand_l after', rig.pose.bones['hand_l'].head, 'mods', [(o.name, [(m.type, getattr(m,'object',None) and m.object.name) for m in o.modifiers]) for o in bpy.data.objects if o.type=='MESH'][:3])
tris = 0
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.data.objects:
    if o.type == 'MESH':
        m = o.evaluated_get(dg).to_mesh(); m.calc_loop_triangles(); tris += len(m.loop_triangles); o.evaluated_get(dg).to_mesh_clear()
print('TRIS', tris, [o.name for o in bpy.data.objects])
bpy.ops.export_scene.gltf(filepath=args["out"], export_format='GLB', export_apply=args.get("apply", True), export_yup=True,
                          export_animations=False, export_skins=not args.get("apply", True), export_morph=not args.get("apply", True))
print('EXPORTED', args["out"])
