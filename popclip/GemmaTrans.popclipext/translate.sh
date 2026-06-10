#!/bin/zsh
# PopClip → GemmaTrans 本地翻译 API
python3 - <<'EOF'
import json, os, urllib.request
try:
    req = urllib.request.Request(
        "http://127.0.0.1:8765/translate",
        data=json.dumps({"text": os.environ.get("POPCLIP_TEXT", "")}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        print(json.load(r)["translation"], end="")
except Exception as e:
    print(f"GemmaTrans 未运行? {e}", end="")
EOF
