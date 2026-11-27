# 按 exclude.txt 去掉审核没通过的照片，每类 80% 训练 20% 测试
import os, random, shutil
ex = set()
if os.path.exists("ml/exclude.txt"):
    for l in open("ml/exclude.txt"):
        l = l.split("#")[0].strip()
        if not l: continue
        c, ids = l.split(":"); ex |= {(c.strip(), int(i)) for i in ids.split(",") if i.strip()}
import json
random.seed(7); shutil.rmtree("ml/split", ignore_errors=True)
for c in sorted(os.listdir("ml/data")):
    order = json.load(open(f"ml/review/{c}.json"))
    keep = [n for i, n in enumerate(order) if (c, i) not in ex and os.path.exists(f"ml/data/{c}/{n}")]
    if len(keep) < 10: print("skip", c, len(keep)); continue
    random.shuffle(keep); k = max(2, len(keep) // 5)
    for part, ns in (("test", keep[:k]), ("train", keep[k:])):
        os.makedirs(f"ml/split/{part}/{c}", exist_ok=True)
        for n in ns: shutil.copy(f"ml/data/{c}/{n}", f"ml/split/{part}/{c}/{n}")
    print(c, "train", len(keep) - k, "test", k)
