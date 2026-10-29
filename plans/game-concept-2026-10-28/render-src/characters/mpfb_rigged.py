import bpy, sys, json
from bl_ext.user_default.mpfb.services import HumanService
from bl_ext.user_default.mpfb.services.faceservice import FaceService
from bl_ext.user_default.mpfb.services.exportservice import ExportService
out = sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
hi = HumanService._create_default_human_info_dict()
hi["phenotype"].update({"gender": 0.0, "age": 0.42, "muscle": 0.45, "weight": 0.48, "height": 0.42, "proportions": 0.65, "cupsize": 0.45, "race": {"asian": 0.1, "caucasian": 0.65, "african": 0.25}})
hi.update({"rig": "game_engine", "eyes": "high-poly.mhclo", "eyebrows": "eyebrow010.mhclo", "eyelashes": "eyelashes03.mhclo", "teeth": "teeth_base.mhclo", "tongue": "tongue01.mhclo", "hair": "ponytail01.mhclo",
           "clothes": ["female_casualsuit01.mhclo", "shoes01.mhclo"], "skin_mhmat": "young_caucasian_female.mhmat", "skin_material_type": "MAKESKIN", "eyes_material_type": "MAKESKIN", "clothes_material_type": "MAKESKIN"})
st = HumanService.get_default_deserialization_settings(); st["subdiv_levels"] = 0
body = HumanService.deserialize_from_dict(hi, st)
units = ["mouthSmileLeft","mouthSmileRight","mouthFrownLeft","mouthFrownRight","browInnerUp","browDownLeft","browDownRight","jawOpen","eyeBlinkLeft","eyeBlinkRight","cheekSquintLeft","cheekSquintRight","eyeSquintLeft","eyeSquintRight","mouthPucker","eyeWideLeft","eyeWideRight"]
FaceService.set_expression(body, {u: 0.001 for u in units}); FaceService.set_expression(body, {u: 0.0 for u in units})
ExportService.bake_modifiers_remove_helpers(body, bake_masks=True, remove_helpers=True)
import numpy as np
kb = body.data.shape_keys.key_blocks; n = len(body.data.vertices)
def co(k): a = np.empty(n*3, dtype=np.float32); k.data.foreach_get('co', a); return a
basis = co(kb['Basis'])
mix = basis.copy()
for k in kb:
    if k.name != 'Basis' and not k.name.startswith('!ex-'): mix += (co(k) - basis) * k.value
ex = {k.name: co(k) - basis for k in kb if k.name.startswith('!ex-')}
body.active_shape_key_index = 0
for k in list(kb)[::-1]:
    if k.name != 'Basis': body.shape_key_remove(k)
kb['Basis'].data.foreach_set('co', mix); body.data.vertices.foreach_set('co', mix)
for name, d in ex.items():
    nk = body.shape_key_add(name=name, from_mix=False); nk.data.foreach_set('co', mix + d); nk.value = 0.0
body.data.update()
print('SHAPEKEYS', [k.name for k in body.data.shape_keys.key_blocks] if body.data.shape_keys else None)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_apply=False, export_skins=True, export_morph=True, export_animations=False, export_yup=True)
print('EXPORTED', out)
