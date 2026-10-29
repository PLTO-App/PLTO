# Builds the two asset sets for the performance test:
#   assets_orig: Poly Haven originals (1K textures, full meshes), untouched
#   work_opt:    resized textures, to be decimated + exported by Blender (optimize_models.py)
import os, shutil, sys, json
from PIL import Image
S, P = sys.argv[1], sys.argv[2]
PH = f'{S}/dl/ph'
MODELS = {  # id: (target_tris, texture_size)
 'electric_stove': (3000, 512), 'vintage_electric_kettle': (2500, 256), 'brass_pot_01': (1500, 256), 'pot_enamel_01': (1500, 256),
 'wooden_cutting_board': (800, 256), 'croissant': (1200, 512), 'wooden_bowl_01': (1200, 256), 'lemon': (500, 256), 'ceramic_vase_01': (1000, 256),
 'metal_jug': (1000, 256), 'tea_set_01': (3000, 512), 'wicker_basket_01': (2000, 512), 'carrot_cake': (2000, 512), 'vintage_cabinet_01': (5000, 512),
 'strawberry_chocolate_cake': (3000, 512), 'round_wooden_table_01': (2000, 512), 'painted_wooden_chair_01': (800, 512), 'standing_chalkboard_01': (2400, 256),
 'potted_plant_02': (8000, 512), 'planter_box_01': (1500, 256), 'fancy_picture_frame_01': (940, 256), 'wooden_display_shelves_01': (3200, 256)}
ENV_TEX = {'wood_floor': 1024, 'plastered_wall_04': 512, 'square_tiled_wall': 512, 'terrazzo_tiles': 512, 'kitchen_wood': 512}
json.dump({k: {'target_tris': v[0], 'tex': v[1]} for k, v in MODELS.items()}, open(f'{P}/models_plan.json', 'w'), indent=1)
for sub in ('assets_orig', 'work_opt'):
    shutil.rmtree(f'{P}/{sub}', ignore_errors=True)
for m, (_, size) in MODELS.items():
    shutil.copytree(f'{PH}/models/{m}', f'{P}/assets_orig/models/{m}')
    shutil.copytree(f'{PH}/models/{m}', f'{P}/work_opt/models/{m}')
    td = f'{P}/work_opt/models/{m}/textures'
    for f in os.listdir(td):
        im = Image.open(f'{td}/{f}'); s = size if ('diff' in f) else max(128, size // 2)
        if im.size[0] > s: im = im.resize((s, s), Image.LANCZOS)
        im.convert('RGB').save(f'{td}/{f}', quality=88)
for t, size in ENV_TEX.items():
    shutil.copytree(f'{PH}/tex/{t}', f'{P}/assets_orig/tex/{t}')
    os.makedirs(f'{P}/assets_opt/tex/{t}', exist_ok=True)
    for n in ('diff', 'rough', 'nor'):
        im = Image.open(f'{PH}/tex/{t}/{n}.jpg'); s = size if n == 'diff' else max(256, size // 2)
        if im.size[0] > s: im = im.resize((s, s), Image.LANCZOS)
        im.convert('RGB').save(f'{P}/assets_opt/tex/{t}/{n}.jpg', quality=88)
print('ok')
