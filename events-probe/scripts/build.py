#!/usr/bin/env python3
"""每天抓一次国内健美/健身赛事，合并手动维护的比赛，生成 public/events.json。

来源：CBCIS 中国健美赛事信息系统（open.musclegame.cn）公开的赛事 API，
网站在 llms.txt 里写明了这个接口，robots.txt 对普通爬虫是 Allow: /。
只取文字信息（名称、日期、地点、组别、链接），不取海报图片。

只用 Python 标准库，GitHub Actions 的 Linux 机器直接能跑。
用法：
  python3 scripts/build.py                 # 联网抓取并生成
  python3 scripts/build.py --raw FILE      # 用存下来的原始数据生成（调试用）
"""
import argparse
import datetime as dt
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = "https://open.musclegame.cn/api/events"
UA = "XTrainingEventsBot/1.0 (personal fitness app; once a day)"
BJ = dt.timezone(dt.timedelta(hours=8))

# 主办方 / 品牌：按比赛名里的关键词认（先匹配的优先）
BRANDS = [
    ("寰际", "寰际"), ("环球", "环球"), ("MEGA", "MEGA"), ("奥赛", "奥赛"), ("Olympia", "奥赛"),
    ("聚力", "聚力"), ("凡星者", "凡星者"), ("舒华", "舒华"), ("卡文诺斯", "卡文诺斯"),
    ("红线", "红线"), ("REDLINE", "红线"), ("WNBF", "WNBF"), ("NPC", "NPC"),
    ("全国健美", "健美协会"), ("中国健美协会", "健美协会"), ("健美协会", "健美协会"),
    ("省健身健美", "省体育局"), ("健身健美公开赛", "省体育局"), ("锦标赛", "健美协会"),
    ("大学生", "大学生赛"), ("高校", "大学生赛"),
]
LEVELS = {"职业赛": "职业赛", "职业卡资格赛": "发卡赛", "商业赛": "商业赛", "校赛": "大学生赛"}
MUNI = ("北京", "上海", "天津", "重庆", "香港", "澳门")


def fetch_all():
    out, page, pages = [], 1, 1
    while page <= pages:
        req = urllib.request.Request(f"{API}?page={page}", headers={"User-Agent": UA, "Accept": "application/json"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    data = json.load(r)
                break
            except Exception as e:  # 网络抖动就等一会儿再试
                if attempt == 3:
                    raise
                print(f"page {page} 失败：{e}，重试", file=sys.stderr)
                time.sleep(5 * (attempt + 1))
        pages = int(data.get("totalPages") or 1)
        out += data.get("events") or []
        print(f"page {page}/{pages}：累计 {len(out)} 场", file=sys.stderr)
        page += 1
        time.sleep(1.5)  # 别给人家服务器压力
    return out


def bj_date(iso):
    if not iso:
        return None
    t = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    return t.astimezone(BJ).date().isoformat()


def city_of(loc, name):
    loc = loc or ""
    for m in MUNI:
        if loc.startswith(m):
            return m
    m = re.search(r"(?:省|自治区)?([^省市区县（(]{2,7}?)(?:市|地区|自治州|盟)", re.sub(r"^.*?(?:省|自治区)", "", loc))
    if m and loc:
        return m.group(1)
    m = re.search(r"[（(]([^）)]{2,6}?)站[）)]", name)
    if m:
        return m.group(1)
    return loc[:6] or None


def brand_of(name):
    for k, v in BRANDS:
        if k.lower() in name.lower():
            return v
    return "其他"


def short_cats(cats):
    seen = []
    for c in cats or []:
        c = re.sub(r"[（(].*?[）)]", "", c).strip()
        if c and c not in seen:
            seen.append(c)
    if len(seen) > 6:
        return "、".join(seen[:6]) + f" 等 {len(seen)} 个项目"
    return "、".join(seen) or None


def convert(e):
    raw = (e.get("name") or "").strip()
    if not raw or "取消" in raw[:6]:
        return None
    flags = re.findall(r"【([^】]+)】", raw)
    name = re.sub(r"【[^】]*】", "", raw).strip()
    start, end = bj_date(e.get("startDate")), bj_date(e.get("endDate"))
    loc = (e.get("location") or "").strip()
    city = city_of(loc, name)
    level = LEVELS.get(e.get("level") or "", "比赛")
    tags = e.get("tags") or []
    if e.get("hasAwards") or (e.get("awardsTotal") or 0) > 0:
        level = "奖金赛" if level in ("商业赛", "比赛") else level
    if level == "比赛" and any("自然" in t for t in tags + [name]):
        level = "自然赛"
    divs = short_cats(e.get("categories"))
    groups = [g for g in (e.get("groups") or []) if g]

    # 简介：只用接口给的事实拼出来
    parts = []
    if loc:
        parts.append(f"地点：{loc}。")
    if start and end and end != start:
        days = (dt.date.fromisoformat(end) - dt.date.fromisoformat(start)).days + 1
        parts.append(f"连比 {days} 天。")
    if divs:
        parts.append(f"项目：{divs}。")
    if groups:
        parts.append(f"组别：{'、'.join(groups)}。")
    award = e.get("awardsTotal") or 0
    if award:
        parts.append(f"总奖金约 {award:,} 元。")
    if flags:
        parts.append("亮点：" + "、".join(flags) + "。")
    if tags:
        parts.append("、".join(tags[:4]) + "。")
    cost = e.get("cost")
    if cost and cost not in ("见费用说明", "见报名说明"):
        parts.append(f"报名费 {cost}。")
    parts.append("报名在微信小程序“健美赛事报名”，以官方页面为准。")

    r = {
        "id": "mg-" + e["id"],
        "date": start,
        "name": name,
        "city": city,
        "org": brand_of(name),
        "level": level,
        "divs": divs,
        "desc": "".join(parts),
        "dy": re.sub(r"^20\d\d\s*", "", name),
        "url": e.get("detailUrl") or f"https://open.musclegame.cn/events/{e['id']}",
        "region": "cn",
        "time": "09:00",
        "est": True,
        "src": "musclegame",
    }
    if end and end != start:
        r["end"] = end
    return {k: v for k, v in r.items() if v not in (None, "")}


def mg_id(url):
    m = re.search(r"musclegame\.cn/events/([0-9a-f]{24})", url or "")
    return m.group(1) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", help="用这个原始 JSON 文件代替联网")
    a = ap.parse_args()

    if a.raw:
        raw = json.load(open(a.raw))
        raw = raw["events"] if isinstance(raw, dict) else raw
    else:
        raw = fetch_all()
        (ROOT / "data").mkdir(exist_ok=True)
        json.dump(raw, open(ROOT / "data/raw-musclegame.json", "w"), ensure_ascii=False, indent=1)

    manual = json.load(open(ROOT / "data/manual.json"))["events"]
    taken = {mg_id(m.get("url")) for m in manual} - {None}

    scraped, seen = [], set()
    for e in raw:
        if not e.get("id") or e["id"] in seen or e["id"] in taken:
            continue  # 手动维护过的同一场比赛以手动为准（id 不变，追赛不丢）
        seen.add(e["id"])
        c = convert(e)
        if c and c.get("date"):
            scraped.append(c)

    if len(scraped) < 20 and not a.raw:
        sys.exit(f"只抓到 {len(scraped)} 场，可能接口变了，这次不更新")

    events = manual + scraped
    events.sort(key=lambda x: (x.get("region", "cn") != "cn", x.get("date") or "9999"))
    out = {
        "updated": dt.datetime.now(BJ).date().isoformat(),
        "source": "国内赛事来自 CBCIS 中国健美赛事信息系统 open.musclegame.cn；全球职业赛手动整理",
        "counts": {"manual": len(manual), "scraped": len(scraped)},
        "events": events,
    }
    (ROOT / "public").mkdir(exist_ok=True)
    json.dump(out, open(ROOT / "public/events.json", "w"), ensure_ascii=False, indent=1)
    print(f"写入 {len(events)} 场（手动 {len(manual)}，自动 {len(scraped)}）", file=sys.stderr)


if __name__ == "__main__":
    main()
