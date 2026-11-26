#!/usr/bin/env python3
"""上传后：等苹果处理完 → 填测试说明 → 加进所有测试群组 → 外部群组提交测试审核。
所有步骤失败都只打印警告，不让整个任务失败（构建已经上传成功）。"""
import json, os, sys, time, urllib.request, urllib.error
import jwt  # PyJWT

KEY_ID = os.environ["ASC_KEY_ID"]; ISSUER = os.environ["ASC_ISSUER_ID"]
KEY = open(os.environ["ASC_KEY_PATH"]).read()
BUNDLE = os.environ["APP_BUNDLE_ID"]; BUILD_NO = os.environ["BUILD_NO"]
NOTES = (os.environ.get("NOTES") or "").strip()[:3900] or "日常更新与修复"
API = "https://api.appstoreconnect.apple.com/v1"

def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                      KEY, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})

def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            t = r.read()
            return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t = e.read().decode(errors="replace")
        return e.code, {"error": t[:600]}

def warn(msg): print("::warning::" + msg)

s, r = call("GET", f"/apps?filter[bundleId]={BUNDLE}")
if s != 200 or not r.get("data"):
    warn(f"找不到 App {BUNDLE}: {s} {r}"); sys.exit(0)
app = r["data"][0]["id"]

# 1. 等构建处理完（最多 45 分钟）
build = None
for i in range(90):
    s, r = call("GET", f"/builds?filter[app]={app}&filter[version]={BUILD_NO}&limit=1")
    if s == 200 and r.get("data"):
        b = r["data"][0]; st = b["attributes"].get("processingState")
        print(f"构建 {BUILD_NO}: {st}")
        if st == "VALID": build = b["id"]; break
        if st in ("FAILED", "INVALID"): warn(f"苹果处理失败: {st}"); sys.exit(0)
    else:
        print(f"还没看到构建 {BUILD_NO}（{s}）")
    time.sleep(30)
if not build: warn("等待苹果处理超时，请在 App Store Connect 手动分发"); sys.exit(0)

# 2. 出口合规（Info.plist 已声明，这里兜底）
call("PATCH", f"/builds/{build}", {"data": {"type": "builds", "id": build,
     "attributes": {"usesNonExemptEncryption": False}}})

# 3. 测试说明（中文 + 英文都写）
s, r = call("GET", f"/builds/{build}/betaBuildLocalizations")
have = {x["attributes"]["locale"]: x["id"] for x in r.get("data", [])} if s == 200 else {}
for loc in ("zh-Hans", "en-US"):
    if loc in have:
        s, r = call("PATCH", f"/betaBuildLocalizations/{have[loc]}", {"data": {"type": "betaBuildLocalizations",
              "id": have[loc], "attributes": {"whatsNew": NOTES}}})
    else:
        s, r = call("POST", "/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations",
              "attributes": {"locale": loc, "whatsNew": NOTES},
              "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
    print(f"测试说明 {loc}: {s}") if s < 300 else warn(f"测试说明 {loc} 失败: {s} {r}")

# 4. 加进所有测试群组
s, r = call("GET", f"/apps/{app}/betaGroups?limit=50")
groups = r.get("data", []) if s == 200 else []
external = False
for g in groups:
    a = g["attributes"]; name = a.get("name")
    if a.get("publicLinkEnabled") and a.get("publicLink"):
        print(f"公开测试链接 {name}: {a['publicLink']}")
    if a.get("isInternalGroup") and a.get("hasAccessToAllBuilds"):
        print(f"内部群组 {name}: 自动获得所有构建"); continue
    s, r = call("POST", f"/betaGroups/{g['id']}/relationships/builds",
                {"data": [{"type": "builds", "id": build}]})
    print(f"加入群组 {name}: {s}") if s < 300 else warn(f"加入群组 {name} 失败: {s} {r}")
    if not a.get("isInternalGroup"): external = True

# 5. 有外部群组就提交测试审核（同一版本号第一次审过后，之后的构建通常秒过）
if external:
    s, r = call("POST", "/betaAppReviewSubmissions",
                {"data": {"type": "betaAppReviewSubmissions",
                          "relationships": {"build": {"data": {"type": "builds", "id": build}}}}})
    print(f"提交外部测试审核: {s}") if s < 300 else warn(f"提交外部测试审核失败: {s} {r}")
print("完成")
