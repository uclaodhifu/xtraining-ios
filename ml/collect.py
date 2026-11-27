# 从 Openverse 和维基共享资源收集可自由使用的器械照片（CC / 公有领域），存到 data/<类别>/，并生成审核用拼图
import json, os, sys, time, io, csv, urllib.parse, urllib.request
from PIL import Image, ImageDraw
UA = {"User-Agent": "xtraining-dataset-builder/1.0 (open-source research)"}
PER = int(os.environ.get("PER_CLASS", "80"))
OK_LIC = {"by", "by-sa", "cc0", "pdm"}
def get(url, t=30):
    r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=t); return r.read()
def openverse(q):
    out = []
    for page in range(1, 6):
        u = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode({"q": q, "page_size": 20, "page": page, "license": "by,by-sa,cc0,pdm", "mature": "false"})
        try: d = json.loads(get(u))
        except Exception as e: print("openverse", q, page, e); break
        for r in d.get("results", []):
            out.append({"src": "openverse", "id": r["id"], "url": r.get("thumbnail") or r["url"], "orig": r.get("foreign_landing_url", ""), "license": r.get("license", ""), "creator": r.get("creator") or "", "title": r.get("title") or ""})
        if page >= d.get("page_count", 1): break
        time.sleep(4)
    return out
def commons(q):
    u = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({"action": "query", "format": "json", "generator": "search", "gsrnamespace": 6, "gsrsearch": q, "gsrlimit": 50, "prop": "imageinfo", "iiprop": "url|extmetadata", "iiurlwidth": 640})
    try: d = json.loads(get(u))
    except Exception as e: print("commons", q, e); return []
    out = []
    for p in (d.get("query", {}).get("pages", {}) or {}).values():
        ii = (p.get("imageinfo") or [{}])[0]; m = ii.get("extmetadata", {})
        lic = (m.get("LicenseShortName", {}).get("value", "")).lower()
        if not any(k in lic for k in ["cc0", "cc by", "public domain", "cc-by"]): continue
        if not p["title"].lower().endswith((".jpg", ".jpeg", ".png")): continue
        out.append({"src": "commons", "id": str(p["pageid"]), "url": ii.get("thumburl") or ii.get("url"), "orig": ii.get("descriptionurl", ""), "license": lic, "creator": m.get("Artist", {}).get("value", "")[:120], "title": p["title"]})
    return out
classes = json.load(open("ml/classes.json"))
only = set(filter(None, os.environ.get("ONLY", "").split(",")))
os.makedirs("ml/review", exist_ok=True)
rows = []
for c in classes:
    if only and c["id"] not in only: continue
    cand, seen = [], set()
    for q in c["q"]:
        for r in openverse(q) + commons(q):
            if r["url"] in seen: continue
            seen.add(r["url"]); cand.append(r)
    d = f"ml/data/{c['id']}"; os.makedirs(d, exist_ok=True)
    got = []
    for r in cand:
        if len(got) >= PER: break
        try:
            im = Image.open(io.BytesIO(get(r["url"], 20))).convert("RGB")
            if min(im.size) < 160: continue
            im.thumbnail((512, 512))
            n = f"{r['src'][0]}{r['id'][:12]}.jpg"; im.save(f"{d}/{n}", quality=88)
            got.append((n, im)); rows.append([c["id"], n, r["src"], r["orig"], r["license"], r["creator"], r["title"]])
        except Exception as e: print("dl", e)
    print(c["id"], "candidates", len(cand), "kept", len(got), flush=True)
    # 审核拼图：每格 150px，左上角编号
    cols = 8; T = 150; R = max(1, (len(got) + cols - 1) // cols)
    sheet = Image.new("RGB", (cols * T, R * T), "white"); dr = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(got):
        t = im.copy(); t.thumbnail((T - 4, T - 4)); x, y = (i % cols) * T, (i // cols) * T
        sheet.paste(t, (x + 2, y + 2)); dr.rectangle([x + 2, y + 2, x + 34, y + 18], fill="black"); dr.text((x + 5, y + 4), str(i), fill="yellow")
    sheet.save(f"ml/review/{c['id']}.jpg", quality=80)
    json.dump([n for n, _ in got], open(f"ml/review/{c['id']}.json", "w"))
with open("ml/review/sources.csv", "a", newline="") as f: csv.writer(f).writerows(rows)
