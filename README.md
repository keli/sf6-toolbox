# SF6 Toolbox

街霸6工具集，目前包含偷帧（Meaty）计算器和 ELO 胜率计算器。

数据来源：[FAT (Frame Assistant Tool)](https://github.com/D4RKONION/FAT) 的 SF6FrameData.json。

## 使用

用浏览器打开 `index.html`（需要本地服务器，因为要加载 JSON 数据）：

```bash
python3 -m http.server
# 然后访问 http://localhost:8000
```

支持中英文切换。

数据加载方式（Meaty 计算器）：
- 先读取 `data/characters.index.json` 角色索引
- 再按角色按需读取 `data/<角色目录>/final.json`
- FAT 原始版本对应 `data/<角色目录>/fat.json`

---

## Meaty 计算器

对每个角色，穷举击倒动作与后续动作序列的所有组合，计算哪些组合能在对手起身时命中持续帧——命中越晚，偷到的帧数越多，攻击方获得的实际帧优势越大。

### 原理

Meaty 是压起身；而**偷帧的本质是 Late Meaty**：动作正常命中时帧优势为 `onHit`，命中越靠后（第 N 个持续帧而非第 1 帧），攻击方额外多 `N-1` 帧优势。最后一帧命中偷帧最多（`+A-1`），即完美 meaty。

注：数据字段 `startup` 表示“首个可命中帧的序号”（例如 5 表示第 5 帧开始可命中），并非 startup 帧数本身；实现内部直接按这个 `U` 口径计算。

```
记：
U = startup（数据里的首个可命中帧序号）
A = active
K1 = 1-based 的击倒后可用帧序号（扣除前置与 delay 之后）

持续帧窗口：[U, U+A-1]
meaty 条件：U <= K1 <= U+A-1
命中持续帧第 N 帧：N = K1 - U + 1
额外偷帧：N - 1
完美 meaty：K1 = U + A - 1
```

当前实现还加入“3F 反打安全窗口”筛选（用于保留仍安全但不偷帧的方案）：

```
记：
Kd = 击倒优势（如 KD +31）
P  = 前置动作总帧（prefix total）
d  = 放帧（delay）
U  = startup（首个可命中帧序号）
A  = active
K1 = Kd - P - d + 1

1) 真正 meaty（起身发生在我持续期内）：
   U <= K1 <= U + A - 1
   N = K1 - U + 1
   stolen = N - 1

2) 非 meaty 但仍安全（起身早于我第1持续帧，但不被 3F 抢先）：
   K1 < U 且 U - K1 <= 3
   N = 1
   stolen = 0

3) 其余情况过滤：
   - K1 > U + A - 1（持续结束仍未到起身）
   - K1 < U 且 U - K1 > 3（会被 3F 反打先命中）
```

### 示例 维加（214HP：KD +31）

以 `66[19f] → 4HK(startup=10, active=4)` 为例：

- 无放帧时：`K1 = 31 - 19 - 0 + 1 = 13`
- `U = 10`，满足 `10 <= 13 <= 13`，所以 `N = 13 - 10 + 1 = 4`，命中帧 `4/4`，偷帧 `+3`
- 放帧后 `K1` 每增加 1f delay 就减少 1：
  - `d=3` 时 `K1=10`，命中帧 `1/4`，偷帧 `0`
  - `d=4~6` 时仍是 `1/4`（不偷帧但仍在 3F 安全窗口内）
  - `d>=7` 时 `U-K1>3`，会被 3F 反打先命中，方案应被过滤

序列结构：默认**第一个动作必须是移动动作**（Drive Rush 或前冲 66），中间可以插入任意动作消耗帧数，**最后一个动作必须是打击动作**。

### 过滤选项

- **击倒来源**：普通命中 / 惩罚反击 (PC) / 全部
- **击倒类型**：普通击倒 / 硬击倒（对手无法后滚）/ 全部
- **前置动作上限**：序列中前置动作数量上限（默认 2）
- **最小帧优势**：命中后的最低帧优势要求（默认 4）
- **仅限安全动作**：过滤防御时 ≤ -4 的收尾动作（默认开启）
- **仅可 cancel 动作**：收尾动作必须可以 cancel 接连招（默认开启）
- **排除可 cancel 击倒源**：排除可被取消、实际不一定形成击倒的动作（默认开启）
- **仅完美 meaty ★**：只显示最后一个持续帧命中的方案
- **允许攻击动作作为前置**：放开前置动作必须是移动的限制

### 结果说明

结果按击倒优势分组，帧数相同的击倒技合并显示。

- **发生(U) / 持续帧**：收尾动作的 `startup(U)`（首个命中帧序号）和持续帧数 A
- **命中帧**：命中发生在第几个持续帧（`n/A`）
- **偷帧**：实际偷取的帧数（`N-1`），★ 表示完美 meaty
- **命中优势**：meaty 命中后的实际帧优势（`onHit + 偷帧`）；若收尾动作本身会击倒则显示 `KD`
- **防御优势**：收尾动作被防住时的帧优势（负数表示不利）

---

## ELO 胜率计算器

根据两名玩家的 ELO 分数，计算各自的胜率预期，以及对局结束后各种结果下的分数变化。

---

## 更新数据

先更新 FAT 基线并重建按角色 FAT 文件/索引：

```bash
python3 build_character_data.py normalize
```

- `normalize` 会：
  - 读取 FAT 基线（默认 `data/sf6framedata.json`）
  - 重写 `data/<角色目录>/fat.json`（包含 `normalized` 字段）
  - 更新 `data/characters.index.json`

如需先在线下载最新 FAT 基线再重建：

```bash
python3 build_character_data.py normalize --download-base
```

## 人工/AI 校对与覆盖

先用官网数据对比 FAT 生成 overrides 候选与冲突清单，再按需人工审阅。

写好覆盖文件后，执行 apply 脚本生成最终 `final.json`：

```bash
python3 apply_character_overrides.py
```

选项：
- 默认行为：生成最终数据时完全复制索引里的 `fatFile`，并跳过全部 overrides
- `--use-overrides`：启用索引里的 `overridesFile` 覆盖逻辑
- `--apply-base fat`（默认）：启用 overrides 时，从索引里的 `fatFile` 开始应用覆盖
- `--apply-base final`：启用 overrides 时，从索引里的 `file` 开始应用覆盖（追加修正）
- `--copy-fat-only`：强制仅复制 FAT（即使传了 `--use-overrides` 也会忽略）
- `--strict`：启用值格式校验

## 从官网重建 Overrides（推荐）

如果你希望忽略旧的 overrides，直接从官网 Frame Data 重新抓取并和 FAT 比对生成新的角色覆盖文件，运行：

```bash
python3 build_official_overrides.py
```

说明：
- 脚本会自动从 `https://www.streetfighter.com/6/character` 读取角色 slug（例如 `vega_mbison`、`gouki_akuma`）。
- 默认优先复用各角色目录下的 `official.json`，不会重复抓网页；只有缺失时才抓取。
- 如需强制重新抓取每个角色页面，使用 `--refresh`。
- 会覆盖现有的 `data/<角色目录>/overrides.json`。
- 会把官网解析后的原始行数据保存到 `data/<角色目录>/official.json` 方便审计。
- 会额外生成差异清单：`data/<角色目录>/official.conflicts.csv` 与汇总 `data/official_overrides.conflicts.csv`。

常用选项：
- `--chars Ryu,Ken`：只处理指定角色（用 `data/characters.index.json` 里的名称）
- `--allow-opaque-hitblock`：允许把 `D` 这类非数值 onHit/onBlock 也写入 overrides（默认跳过）
- `--timeout 40`：设置网络超时秒数

## 文件结构

```
sf6-toolbox/
├── build_character_data.py         # 读取 FAT 并生成按角色 fat/source 索引
├── build_official_overrides.py     # 抓官网 frame 并与 FAT 对比，重建 overrides
├── apply_character_overrides.py    # 将 overrides.json 应用到 fat.json 生成最终数据
├── AI_REVIEW_GUIDE.md              # AI 校对工作流说明
├── index.html                      # 网页工具集
├── data/
│   ├── sf6framedata.json           # FAT 基线数据（完整）
│   ├── characters.index.json       # 角色索引（前端先读取）
│   ├── official_overrides.conflicts.csv  # 官网比对总冲突清单
│   ├── 角色目录/
│   │   ├── fat.json                 # FAT 来源数据（含 normalized）
│   │   ├── final.json               # 正式使用数据（apply 脚本生成）
│   │   ├── overrides.json           # 人工/AI 校对后的覆盖值
│   │   ├── official.json            # 官网抓取的原始 frame 解析结果
│   │   └── official.conflicts.csv   # 该角色官网 vs FAT 冲突清单
│   └── i18n-zh.json                 # 中文文案
└── README.md
```
