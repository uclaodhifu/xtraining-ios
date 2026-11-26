#!/usr/bin/env python3
"""每次云端打包都会新建一张开发证书（私钥随机器销毁，旧证书没用了），
苹果账号证书数量有上限，满了就打包失败。这里在打包前删掉旧的开发证书。
只删开发证书，不动发布证书；失败只打印警告。"""
import json, os, time, urllib.request, urllib.error
import jwt

KEY = open(os.environ["ASC_KEY_PATH"]).read()
API = "https://api.appstoreconnect.apple.com/v1"

def call(method, path):
    now = int(time.time())
    tok = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
                     KEY, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": "Bearer " + tok})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            t = r.read(); return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode(errors="replace")[:400]}

s, r = call("GET", "/certificates?limit=200&fields[certificates]=certificateType,displayName,expirationDate")
if s != 200:
    print(f"::warning::读不到证书列表: {s} {r}"); raise SystemExit(0)
for c in r.get("data", []):
    a = c["attributes"]; t = a.get("certificateType", "")
    print(f"证书 {t} {a.get('displayName')} 到期 {a.get('expirationDate')}")
    if t in ("DEVELOPMENT", "IOS_DEVELOPMENT"):
        s2, r2 = call("DELETE", f"/certificates/{c['id']}")
        print(f"  删除旧开发证书 → {s2}" + ("" if s2 in (200, 204) else f" {r2}"))
