#!/bin/zsh
# PopClip → GemmaTrans 本地翻译 API
python3 - <<'EOF'
import json, os, urllib.request, urllib.error
try:
    req = urllib.request.Request(
        "http://127.0.0.1:8765/translate",
        data=json.dumps({"text": os.environ.get("POPCLIP_TEXT", "")}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        print(json.load(r)["translation"], end="")
except urllib.error.HTTPError as e:
    # 服务在运行但翻译失败：显示服务端给的真实原因
    try:
        detail = json.loads(e.read()).get("error", "")
    except Exception:
        detail = ""
    print(f"翻译失败({e.code}): {detail or e.reason}", end="")
except urllib.error.URLError:
    print("GemmaTrans 未运行（连接不上 127.0.0.1:8765）", end="")
except Exception as e:
    print(f"出错: {e}", end="")
EOF
