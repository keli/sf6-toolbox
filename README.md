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

---

## Meaty 计算器

对每个角色，穷举击倒动作与后续动作序列的所有组合，计算哪些组合能在对手起身时命中持续帧——命中越晚，偷到的帧数越多，攻击方获得的实际帧优势越大。

### 原理

Meaty 的本质是**偷帧**：动作正常命中时帧优势为 `onHit`，但若命中发生在第 N 个持续帧（而非第 1 帧），攻击方额外多 `N-1` 帧优势，因为对手的受身硬直从第 N 帧才开始计算，而攻击方的后摇从第 1 帧就开始了。最后一帧命中偷帧最多（`+A-1`），即完美 meaty。

```
击倒优势 = K 帧
后续动作：前摇 S 帧，持续 A 帧
持续帧窗口：[S, S+A-1]

meaty 条件：S <= K <= S+A-1
命中持续帧第 N 帧：N = K - S + 1，额外偷帧 = N - 1
完美 meaty：K = S+A-1（最后一帧命中，偷帧 A-1 帧）
```

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

- **前摇 / 持续**：收尾动作的前摇帧数 S 和持续帧数 A
- **命中帧**：命中发生在第几个持续帧（`n/A`）
- **偷帧**：实际偷取的帧数（`N-1`），★ 表示完美 meaty
- **命中优势**：meaty 命中后的实际帧优势（`onHit + 偷帧`）；若收尾动作本身会击倒则显示 `KD`
- **防御优势**：收尾动作被防住时的帧优势（负数表示不利）

---

## ELO 胜率计算器

根据两名玩家的 ELO 分数，计算各自的胜率预期，以及对局结束后各种结果下的分数变化。

---

## 更新数据

```bash
python3 fetch_data.py --update
```

## 文件结构

```
sf6-toolbox/
├── fetch_data.py           # 获取并更新帧数据
├── index.html              # 网页工具集
├── data/
│   └── sf6framedata.json   # 完整数据源
└── README.md
```

## 角色列表（29名）

A.K.I. / Akuma / Alex / Blanka / C.Viper / Cammy / Chun-Li / Dee Jay / Dhalsim / E.Honda / Ed / Elena / Guile / Jamie / JP / Juri / Ken / Kimberly / Lily / Luke / M.Bison / Mai / Manon / Marisa / Rashid / Ryu / Sagat / Terry / Zangief
