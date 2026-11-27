// 备忘录解析脚本（嵌在代码里，不再单独放 .js 文件——有的签名 App 遇到包里的 .js 会导入失败）
let notesParserJS = ##"""
// 备忘录训练记录解析（从网页版 lib/importNotes.js 搬来，App 里用 JavaScriptCore 跑）
// 把 iPhone 备忘录里手写的训练记录解析成手记的记录。
// 支持的写法举例：
//   11月1日 胸+肩 / 2026.11.1 / 11/1 / 11-1 / 11.1号 周六   ← 日期行，开始新的一次训练
//   卧推 60kg 8 8 6          ← 重量 + 每组次数
//   卧推 60*8 65*6 65x5      ← 每组 重量×次数
//   深蹲 100x5x5             ← 重量×次数×组数
//   侧平举 8kg 3组x15 / 3组 每组15个 / 15个×3组 / 4x12 20kg
//   卧推 60公斤 10次 3组      ← 重量、次数、组数分开写
//   引体向上 10 8 6          ← 自重，每组次数
//   跑步 30分钟 / 跑步 5km 30min   ← 有氧只记分钟
//   动作名单独一行，下面每行一组也行：
//     卧推
//     60kg 12个
//     第2组 65kg×10
const PARTS = {
  胸: ["卧推", "上斜卧推", "哑铃卧推", "蝴蝶机夹胸", "双杠臂屈伸"],
  肩: ["推举", "哑铃推举", "侧平举", "面拉", "反向飞鸟"],
  背: ["引体向上", "高位下拉", "杠铃划船", "坐姿划船", "硬拉"],
  腿: ["深蹲", "腿举", "罗马尼亚硬拉", "臀推", "腿弯举", "腿屈伸"],
  手臂: ["二头弯举", "锤式弯举", "三头下压", "窄距卧推", "过头臂屈伸"],
  有氧: ["跑步", "快走", "单车", "椭圆机", "划船机", "跳绳", "爬楼机", "游泳"],
};
const ymd = (d = new Date()) => { const z = new Date(d); z.setMinutes(z.getMinutes() - z.getTimezoneOffset()); return z.toISOString().slice(0, 10); };

const PART_WORDS = [
  ["有氧", /跑步|慢跑|跑|单车|动感|骑行|椭圆|爬坡|爬楼|游泳|跳绳|划船机|有氧|快走|徒步|楼梯机/],
  ["手臂", /弯举|二头|三头|臂屈伸|下压|手臂|小臂|窄距|锤式|牧师/],
  ["肩", /反向飞鸟|后束|肩|推举|侧平举|前平举|面拉|耸肩|阿诺德|直立划船/],
  ["胸", /胸|卧推|夹胸|飞鸟|俯卧撑|双杠|蝴蝶机|平推|推胸/],
  ["背", /背|引体|下拉|划船|硬拉|山羊挺身|直臂|高位|T杠|大剪刀|引体/i],
  ["腿", /腿|蹲|臀|箭步|弓步|提踵|罗马尼亚|腿举|髋/],
];
function partOfName(name) {
  for (const [p, list] of Object.entries(PARTS)) if (list.includes(name)) return p;
  for (const [p, re] of PART_WORDS) if (re.test(name)) return p;
  return null;
}
// 日期后面写的“胸+肩”“练背”“腿日”这类部位
const partsInText = (t) => {
  const out = [];
  for (const p of ["胸", "肩", "背", "腿"]) if (t.includes(p)) out.push(p);
  if (/手臂|二头|三头|臂/.test(t)) out.push("手臂");
  if (/有氧|跑步|单车/.test(t)) out.push("有氧");
  return out;
};

const fmt = (y, m, d) => `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
// 没写年份时：用今年，如果比今天还晚就算去年
const guessYear = (m, d) => { const now = new Date(), y = now.getFullYear(); return new Date(y, m - 1, d) > now ? y - 1 : y; };

// 先统一写法：全角数字/符号、各种乘号、单位
function normalize(s) {
  return String(s)
    .replace(/[０-９]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0))
    .replace(/[．。](?=\d)/g, ".")
    .replace(/[xX×*ｘＸ✖✕✗乘]️?/g, "×")
    .replace(/\s*(公斤|KG|Kg|kgs?)\b/g, "kg").replace(/公斤/g, "kg")
    .replace(/(\d)\s*(pounds?|lbs?|磅|#)/gi, "$1lb")
    .replace(/(\d)\s*(minutes?|mins?|分钟|分)(?![a-z])/gi, "$1min")
    .replace(/(\d)\s*(小时|h)(?![a-z])/gi, "$1hr")
    .replace(/(\d)\s*(公里|km|千米)/gi, "$1km")
    .replace(/(\d)\s*(reps?|个|次|下)/gi, "$1次")
    .replace(/(\d)\s*(sets?|组)/gi, "$1组")
    .replace(/[，,、；;|｜/]/g, " ")
    .replace(/[（）()【】\[\]]/g, " ")
    .replace(/\s+/g, " ").trim();
}

function parseDate(line, year) {
  const wk = /^\s*(?:周|星期|礼拜)[一二三四五六日天]\s*/;
  let m = line.match(/^\s*(20\d{2})\s*[年.\-/]\s*(\d{1,2})\s*[月.\-/]\s*(\d{1,2})\s*[日号]?/);
  if (m) return { date: fmt(+m[1], +m[2], +m[3]), rest: line.slice(m[0].length).replace(wk, "") };
  m = line.match(/^\s*(\d{1,2})\s*(?:月|[.\-/])\s*(\d{1,2})\s*[日号]?(?!\s*(?:kg|lb|斤|次|组|min|km|\d|[×.]\d))/i);
  if (m && +m[1] >= 1 && +m[1] <= 12 && +m[2] >= 1 && +m[2] <= 31) {
    const rest = line.slice(m[0].length);
    // “11.5 胸”是日期；但“12.5 10次”这种是重量，上面的排除已经挡掉了
    return { date: fmt(year(+m[1], +m[2]), +m[1], +m[2]), rest: rest.replace(wk, "") };
  }
  // “今天/昨天”只在后面没别的话（或只写了部位）时才当日期，免得“今天状态一般”被当成新的一次训练
  const tail = line.replace(/^\s*(今天|今日|昨天)\s*(练|训练)?/, "");
  if (/^\s*(今天|今日|昨天)/.test(line) && tail.trim() && !isPartOnly(tail.trim())) return null;
  if (/^\s*(今天|今日)/.test(line)) return { rel: true, date: ymd(), rest: line.replace(/^\s*(今天|今日)/, "") };
  if (/^\s*昨天/.test(line)) { const d = new Date(); d.setDate(d.getDate() - 1); return { rel: true, date: ymd(d), rest: line.replace(/^\s*昨天/, "") }; }
  return null;
}

const num = (s) => String(Math.round(parseFloat(s) * 100) / 100);
const N = "(\\d+(?:\\.\\d+)?)";
const W = "(kg|斤|lb)?";
let DEF_LB = false;   // 没写单位的数字当磅
let TO_LB = false;    // App 里用的单位是磅：导进来的重量都换成磅，否则都换成公斤
const r1 = (x) => { const r = Math.round(x * 10) / 10; return String(Math.abs(r - Math.round(r)) < 0.051 ? Math.round(r) : r); };
// 一个重量换成 App 的单位：写了 lb/磅 的、写了 kg/公斤/斤 的、没写单位的（按 DEF_LB）
function wOf(v, u) {
  u = (u || "").toLowerCase(); if (!u) u = DEF_LB ? "lb" : "kg";
  let x = parseFloat(v);
  if (u === "斤") { x = x / 2; u = "kg"; }
  if (u === "lb") return TO_LB ? num(x) : r1(x * 0.45359237);
  return TO_LB ? r1(x * 2.20462262) : num(x);
}
// 磅换公斤，保留一位小数（135 磅 → 61.2）
const lb2kg = (v) => String(Math.round(parseFloat(v) * 0.45359237 * 10) / 10);
// 体重：kg / 斤 / 磅
const bwKg = (v, u) => { u = (u || "").toLowerCase(); if (!u && DEF_LB) u = "lb"; return u === "斤" ? num(v / 2) : /lb|磅|pound/.test(u) ? lb2kg(v) : num(v); };

// 解析一段“组”的写法，返回 { sets, min }（min 是有氧的分钟数）
function parseSets(raw) {
  let t = ` ${raw} `.replace(/第\s*\d+\s*组/g, " ").replace(/每组|每边|单边|单手|递减|力竭|热身|正式组?|RPE\s*\d+(\.\d+)?/gi, " ").replace(/\s+/g, " ");
  // 没写单位的重量按导入时选的单位算（选了“磅”就换成公斤）
  const kgOf = wOf;
  let m;

  // 有氧：分钟 / 小时
  const hr = t.match(new RegExp(`${N}\\s*hr`)), mn = t.match(new RegExp(`${N}\\s*min`));
  if (hr || mn) return { sets: [], min: num((hr ? parseFloat(hr[1]) * 60 : 0) + (mn ? parseFloat(mn[1]) : 0)) };

  const unitW = t.match(new RegExp(`${N}\\s*(kg|斤|lb)`, "i"));
  const loneW = unitW ? kgOf(unitW[1], unitW[2].toLowerCase()) : "";
  const rep = (s, r, w = loneW) => Array.from({ length: Math.min(+s, 20) }, () => ({ w, r: num(r) }));

  // 重量×次数×组数：100×5×5 / 20kg×10×3
  if ((m = t.match(new RegExp(`${N}\\s*${W}\\s*×\\s*${N}\\s*次?\\s*×\\s*${N}\\s*组?`, "i")))) return { sets: rep(m[4], m[3], kgOf(m[1], (m[2] || "").toLowerCase())) };
  // 组数和次数写明：3组×15 / 3组15次 / 15次×3组 / 15次3组 / 10次 3组
  if ((m = t.match(new RegExp(`${N}\\s*组\\s*×?\\s*${N}\\s*次?`)))) return { sets: rep(m[1], m[2]) };
  if ((m = t.match(new RegExp(`${N}\\s*次\\s*×?\\s*${N}\\s*组`)))) return { sets: rep(m[2], m[1]) };
  // 只写了组数和一个次数：“3组 12” 或 “12 3组”
  if ((m = t.match(new RegExp(`${N}\\s*组`)))) {
    const left = t.replace(m[0], " ").replace(new RegExp(`${N}\\s*(kg|斤|lb)`, "gi"), " ");
    const r = left.match(/(\d+)/);
    if (r) return { sets: rep(m[1], r[1]) };
  }
  // 重量后面跟 组×次：“90kg 1×10 80kg 1×8 70kg 1×12”“12.5kg 1×12 1×10”“47kg 2×10”
  // 没跟组×次的重量（比如最后的“19kg”）算一组，次数空着
  if (unitW && new RegExp(`(^|\\s)${N}\\s*×\\s*${N}`).test(t)) {
    const sets = [], toks = [...t.matchAll(new RegExp(`${N}\\s*(kg|斤|lb)|${N}\\s*×\\s*${N}`, "gi"))];
    let w = loneW, used = true, seen = false;
    for (const k of toks) {
      if (k[1]) { if (!used) sets.push({ w, r: "" }); w = kgOf(k[1], k[2].toLowerCase()); used = !seen && sets.length > 0; seen = true; continue; }
      const a = +k[3], b = +k[4], n = Math.min(a, b), r = Math.max(a, b);
      if (n <= 10) sets.push(...rep(n, r, w)); else sets.push({ w: num(a), r: num(b) });
      used = true;
    }
    if (!used) sets.push({ w, r: "" });
    return { sets };
  }
  // 多个 重量×次数：60×8 65×6；单独写了重量时“4×12”当成 组×次
  const pairs = [...t.matchAll(new RegExp(`${N}\\s*${W}\\s*×\\s*${N}`, "gi"))];
  if (pairs.length === 1 && unitW && !pairs[0][2] && +pairs[0][1] <= 10 && !t.includes(`${pairs[0][1]}kg`)) return { sets: rep(pairs[0][1], pairs[0][3]) };
  if (pairs.length) {
    let last = "";
    return { sets: pairs.map((p) => { const w = kgOf(p[1], (p[2] || "").toLowerCase()); last = w; return { w, r: num(p[3]) }; }).map((s) => ({ ...s, w: s.w || last })) };
  }
  // 重量 + 次数列表 / 只有次数：“60kg 8 8 6”“65kg 10 70kg 8”“10 8 6”
  const nums = [...t.matchAll(new RegExp(`${N}\\s*(kg|斤|lb|次)?`, "gi"))].filter((x) => x[1]);
  if (!nums.length) return { sets: [] };
  const sets = [];
  let w = "";
  const anyUnit = nums.some((x) => x[2] && x[2] !== "次");
  // 没写单位、大小交替（60 8 65 6，原来是 60/8 65/6）：两两一组 重量 次数
  if (!anyUnit && nums.length >= 4 && nums.length % 2 === 0 && nums.every((x, i) => (i % 2 ? +x[1] <= 25 : +x[1] > 25))) {
    for (let i = 0; i < nums.length; i += 2) sets.push({ w: num(nums[i][1]), r: num(nums[i + 1][1]) });
    return { sets };
  }
  // 没写单位：第一个数明显比后面大（比如 60 12 10 8），当成重量
  if (!anyUnit && nums.length >= 2 && +nums[0][1] > 25 && nums.slice(1).every((x) => +x[1] <= 25)) w = num(nums.shift()[1]);
  nums.forEach((x) => { const u = (x[2] || "").toLowerCase(); if (u && u !== "次") w = kgOf(x[1], u); else sets.push({ w, r: num(x[1]) }); });
  // 只写了重量没写次数（比如“硬拉 140kg”）：记一组，次数空着
  if (!sets.length && w) sets.push({ w, r: "" });
  return { sets };
}

// 从一行里分出“动作名”和后面的数字部分；动作名里可以有数字（“45度上斜卧推”“T杠划船”）
function splitLine(body) {
  const re = /(\d+(?:\.\d+)?)\s*(?=kg|斤|lb|×|次|组|min|hr|km|\s|$)/g;
  let m;
  while ((m = re.exec(body))) {
    const name = body.slice(0, m.index).replace(/[\s:：\-—~～]+$/, "").trim();
    // 名字后面紧跟“度/号/杠”之类说明是名字的一部分
    if (/[度°号]$/.test(body.slice(0, m.index + m[0].length).trim())) continue;
    return { name, rest: body.slice(m.index) };
  }
  return { name: body.replace(/[\s:：\-—]+$/, "").trim(), rest: "" };
}

const isPartOnly = (s) => /^(练|今天练|训练)?\s*[胸肩背腿手臂有氧+＋&和与、\s]+(日|天|训练|部)?\s*[:：]?$/.test(s) && partsInText(s).length > 0;

let seq = 0;
function parseNotes(text, year = guessYear) {
  const workouts = [];
  let cur = null, lastEx = null;
  const start = (date, rest) => {
    const title = rest.replace(/^[\s:：\-—·]+/, "").trim();
    cur = { date, parts: partsInText(title), title: title && !isPartOnly(title) ? title.slice(0, 30) : "", exercises: [], note: [], weight: "" };
    workouts.push(cur); lastEx = null;
  };
  const ensure = () => { if (!cur) start(ymd(), ""); };
  const addEx = (name, r) => {
    ensure();
    const p = partOfName(name);
    const ex = p === "有氧" || r.min ? { name, sets: [{ w: "", r: "", min: r.min || "" }] } : { name, sets: r.sets };
    cur.exercises.push(ex); lastEx = ex;
    if (p && !cur.parts.includes(p)) cur.parts.push(p);
  };

  for (const raw of String(text).split(/\r?\n/)) {
    let line = raw.replace(/^[\s•·\-–—*▪︎◦>✅☑️✔️🔹🔸]+/u, "").replace(/^\d+\s*[.、)）]\s*(?=\D)/, "").trim();
    if (!line) continue;
    const d = parseDate(line, year);
    // 中间冒出来的“今天练肩”：已经在一次训练里了，就只当部位，不另起一天
    if (d?.rel && cur) { partsInText(d.rest).forEach((p) => cur.parts.includes(p) || cur.parts.push(p)); continue; }
    if (d) {
      const dbw = d.rest.match(/体重\s*[:：]?\s*(\d{2,3}(?:\.\d+)?)\s*(kg|公斤|斤|lbs?|磅|pounds?)?/i);
      if (dbw) d.rest = d.rest.replace(dbw[0], " ");
      start(d.date, d.rest.replace(/^\s*[:：]/, ""));
      if (dbw) cur.weight = bwKg(dbw[1], dbw[2]);
      line = d.rest.replace(/^\s*[:：]/, "").trim();
      if (!line || isPartOnly(line) || !/\d/.test(line)) continue;
    }
    line = normalize(line).replace(/第\s*[一二三四五六七八九十\d]+\s*组\s*[:：]?/g, " ").replace(/自重|徒手/g, " ").replace(/\s+/g, " ").trim();
    if (isPartOnly(line)) { ensure(); partsInText(line).forEach((p) => cur.parts.includes(p) || cur.parts.push(p)); continue; }

    // 体重：单独一行或写在日期后面，记到体重里，不当动作
    const bw = line.match(/体重\s*[:：]?\s*(\d{2,3}(?:\.\d+)?)\s*(kg|斤|lb)?/);
    if (bw) { ensure(); cur.weight = bwKg(bw[1], bw[2]); line = line.replace(bw[0], " ").trim(); if (!line) continue; }
    line = line.replace(/^([a-zA-Z])\s+(?=[\u4e00-\u9fa5])/, (_, c) => c.toUpperCase());
    const { name, rest } = splitLine(line);
    // 整行只有数字：接在上一个动作后面，算多一组（或几组）
    if (!name || /^第?\s*$/.test(name)) {
      const r = parseSets(rest);
      if (lastEx && r.sets.length && !lastEx.sets[0]?.min) { lastEx.sets.push(...r.sets); continue; }
      if (lastEx && r.min) { lastEx.sets = [{ w: "", r: "", min: r.min }]; continue; }
      ensure(); cur.note.push(raw.trim()); continue;
    }
    // 备注、感受这类话直接当备注
    if (/备注|感觉|状态|注意|疼|痛|累|酸|舒服|[：:]\s*\S/.test(name)) { ensure(); cur.note.push(raw.trim()); lastEx = null; continue; }
    // 只有名字没有数字：可能是动作名单独一行，下面几行才是组
    if (!rest) {
      if (partOfName(name) || name.length <= 10 && !/[，。！？!?]/.test(name)) {
        ensure();
        const ex = { name, sets: [] }; cur.exercises.push(ex); lastEx = ex;
        const p = partOfName(name); if (p && !cur.parts.includes(p)) cur.parts.push(p);
      } else { ensure(); cur.note.push(raw.trim()); lastEx = null; }
      continue;
    }
    const r = parseSets(rest);
    if (!r.sets.length && !r.min) { ensure(); cur.note.push(raw.trim()); continue; }
    addEx(name, r);
  }

  const out = workouts.map((w) => {
    // 只有名字、下面没跟组的动作：如果像动作就留着（组空着），不像就当备注
    const exercises = [];
    w.exercises.forEach((x) => { if (x.sets.length) exercises.push(x); else if (partOfName(x.name)) exercises.push({ ...x, sets: [{ w: "", r: "" }] }); else w.note.push(x.name); });
    return { ...w, exercises };
  }).filter((w) => w.exercises.length || w.note.length).map((w) => {
    const order = Object.keys(PARTS);
    const id = "n" + hash(w.date + JSON.stringify(w.exercises));
    return { id, createdAt: Date.now() + seq++, date: w.date, parts: w.parts.sort((a, b) => order.indexOf(a) - order.indexOf(b)), title: w.title, duration: "", mood: null, weight: w.weight || "", exercises: w.exercises, note: w.note.join("\n"), source: "notes" };
  });
  // 只记了体重、没练的那天：不算训练，单独给出来记到体重里
  out.weights = workouts.filter((w) => w.weight && !out.some((o) => o.date === w.date)).map((w) => ({ date: w.date, kg: w.weight }));
  return out;
}
function hash(s) { let h = 5381; for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }

// App 调用入口：返回 JSON 字符串 {entries, weights}
function xtParse(text, fixedYear, unit, appLb) {
  TO_LB = !!appLb;
  // unit：1 = 公斤，2 = 磅，其他 = 自动（写 lb/磅 的比写 kg/公斤 的多，就把没写单位的也当磅）
  const t = normalize(text), nLb = (t.match(/\dlb/g) || []).length, nKg = (t.match(/\d\s*kg/g) || []).length;
  DEF_LB = unit === 2 || (unit !== 1 && (nLb > nKg || (nLb === nKg && TO_LB)));
  // fixedYear > 0：只写了月日的日期都按这一年；否则按今天往前推
  const out = parseNotes(text, fixedYear > 0 ? (() => fixedYear) : guessYear);
  const weights = (out.weights || []).slice();
  out.forEach((w) => { if (w.weight) weights.push({ date: w.date, kg: +w.weight }); });
  return JSON.stringify({ entries: out.map((w) => ({ ...w })), weights: weights.map((x) => ({ date: x.date, kg: +x.kg })) });
}

"""##
