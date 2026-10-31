#!/usr/bin/env bash
# Points Godot's Android export at a signing keystore. The password is read from the environment, never from a file in the repository.
#   PLTO_KEY_PASS='...' tools/use_signing_key.sh /path/to/plto-virtual-debug.keystore [alias]
# Also sets the Android SDK and JDK paths if PLTO_ANDROID_SDK / PLTO_JAVA_HOME are given.
set -eu
ks="${1:?path to the keystore}"; alias="${2:-androiddebugkey}"; : "${PLTO_KEY_PASS:?set PLTO_KEY_PASS to the keystore password}"
[ -f "$ks" ] || { echo "no such keystore: $ks"; exit 1; }
cfg="$HOME/.config/godot/editor_settings-4.5.tres"; mkdir -p "$(dirname "$cfg")"; [ -f "$cfg" ] || printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' > "$cfg"
python3 -I - "$cfg" "$ks" "$alias" "${PLTO_ANDROID_SDK:-}" "${PLTO_JAVA_HOME:-}" <<'PY'
import os, sys
cfg, ks, alias, sdk, jdk = sys.argv[1:6]
vals = {"export/android/debug_keystore": ks, "export/android/debug_keystore_user": alias, "export/android/debug_keystore_pass": os.environ["PLTO_KEY_PASS"]}
if sdk: vals["export/android/android_sdk_path"] = sdk
if jdk: vals["export/android/java_sdk_path"] = jdk
lines = open(cfg, encoding="utf-8").read().split("\n")
for k, v in vals.items():
    row = '%s = "%s"' % (k, v.replace('"', '\\"'))
    for i, l in enumerate(lines):
        if l.startswith(k + " ="): lines[i] = row; break
    else: lines.append(row)
open(cfg, "w", encoding="utf-8").write("\n".join(lines).rstrip("\n") + "\n")
print("godot export settings updated for", ks)
PY
