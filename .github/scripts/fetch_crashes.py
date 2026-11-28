#!/usr/bin/env python3
"""拉 TestFlight 崩溃报告，只打印崩溃线程和异常信息（仓库公开，不打印测试员邮箱等个人信息）。"""
import json, os, re, time, urllib.request, urllib.error
import jwt
KEY_ID = os.environ["ASC_KEY_ID"]; ISSUER = os.environ["ASC_ISSUER_ID"]
KEY = open(os.environ["ASC_KEY_PATH"]).read()
BUNDLE = os.environ.get("APP_BUNDLE_ID", "com.kaigreen.xtraining")
API = "https://api.appstoreconnect.apple.com/v1"
def token():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, KEY, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def get(path):
    req = urllib.request.Request(path if path.startswith("http") else API + path, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, {"error": e.read().decode(errors="replace")[:800]}
def filt(log):
    out, keep, lines = [], False, log.splitlines()
    for ln in lines:
        if re.match(r"^(Exception Type|Exception Codes|Exception Reason|Termination Reason|Triggered by Thread|Crashed Thread|Version|OS Version|Hardware Model|Code Type|Exception Subtype|Application Specific Information|Exception Note)", ln) or "Fatal error" in ln or "fatalError" in ln:
            out.append(ln)
        if re.match(r"^(Thread \d+ Crashed|Last Exception Backtrace)", ln): keep = True; out.append(""); out.append(ln); continue
        if keep:
            if not ln.strip(): keep = False; continue
            out.append(ln)
    return "\n".join(out) if out else log[:6000]
s, r = get(f"/apps?filter[bundleId]={BUNDLE}")
app = r["data"][0]["id"]; print("app", app)
s, r = get(f"/apps/{app}/betaFeedbackCrashSubmissions?limit=8&sort=-createdDate&include=build")
print("list", s, (r.get("error") or "")[:400])
builds = {b["id"]: b["attributes"].get("version") for b in r.get("included", []) if b["type"] == "builds"}
for sub in r.get("data", []):
    a = sub["attributes"]; bid = (sub.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
    print("=" * 70)
    print("id", sub["id"], "| 时间", a.get("createdDate"), "| 构建", builds.get(bid), "| 机型", a.get("deviceModel"), "| 系统", a.get("osVersion"))
    if a.get("comment"): print("留言:", a["comment"])
    s2, r2 = get(f"/betaFeedbackCrashSubmissions/{sub['id']}/crashLog")
    if s2 != 200: print("crashLog", s2, r2.get("error", "")[:400]); continue
    txt = (r2.get("data") or {}).get("attributes", {}).get("logText") or ""
    print(filt(txt))
