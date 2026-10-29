"""Download the Poly Haven assets used by the perf test, verifying every file against the md5 published by the Poly Haven API.
Usage: python3 -I ph_download.py <out_dir>   (out_dir becomes <out_dir>/models/<id>/, <out_dir>/tex/<id>/{diff,rough,nor}.jpg, <out_dir>/sky.hdr)
"""
import hashlib, json, os, sys, urllib.request

OUT = sys.argv[1]
MODELS = ['electric_stove', 'vintage_electric_kettle', 'brass_pot_01', 'pot_enamel_01', 'wooden_cutting_board', 'croissant', 'wooden_bowl_01', 'lemon',
          'ceramic_vase_01', 'metal_jug', 'tea_set_01', 'wicker_basket_01', 'carrot_cake', 'vintage_cabinet_01', 'strawberry_chocolate_cake',
          'round_wooden_table_01', 'painted_wooden_chair_01', 'standing_chalkboard_01', 'potted_plant_02', 'planter_box_01', 'fancy_picture_frame_01',
          'wooden_display_shelves_01']
TEXTURES = ['wood_floor', 'plastered_wall_04', 'square_tiled_wall', 'terrazzo_tiles', 'kitchen_wood']
UA = {'User-Agent': 'plto-perf-test/1.0'}


def get(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
                return r.read()
        except Exception as e:
            if attempt == 3:
                raise
            print('retry', url, e, flush=True)


def fetch(url, md5, dest):
    data = get(url)
    got = hashlib.md5(data).hexdigest()
    if got != md5:
        sys.exit(f'MD5 MISMATCH {url}: expected {md5}, got {got}')
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, 'wb').write(data)
    return len(data)


def api(asset):
    return json.loads(get(f'https://api.polyhaven.com/files/{asset}'))


total = 0
for m in MODELS:
    g = api(m)['gltf']['1k']['gltf']
    d = f'{OUT}/models/{m}'
    total += fetch(g['url'], g['md5'], f'{d}/{m}.gltf')
    for rel, inc in g['include'].items():
        total += fetch(inc['url'], inc['md5'], f'{d}/{rel}')
    print('model', m, 'ok', flush=True)
for t in TEXTURES:
    f = api(t)
    for name, key in (('diff', 'Diffuse'), ('rough', 'Rough'), ('nor', 'nor_gl')):
        e = f[key]['1k']['jpg']
        total += fetch(e['url'], e['md5'], f'{OUT}/tex/{t}/{name}.jpg')
    print('tex', t, 'ok', flush=True)
e = api('kiara_1_dawn')['hdri']['1k']['hdr']
total += fetch(e['url'], e['md5'], f'{OUT}/sky.hdr')
print('hdri ok; total MB', round(total / 1048576, 1))
