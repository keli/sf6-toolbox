# SF6 Meaty Calculator

街霸6偷帧（meaty）方案枚举工具。对每个角色，穷举击倒动作与后续动作序列的所有组合，计算哪些组合能在对手起身时命中持续帧——命中越晚，偷到的帧数越多，攻击方获得的实际帧优势越大。

数据来源：[FAT (Frame Assistant Tool)](https://github.com/D4RKONION/FAT) 的 SF6FrameData.json。

## 原理

Meaty 的本质是**偷帧**：动作正常命中时帧优势为 `onHit`，但若命中发生在第 N 个持续帧（而非第 1 帧），攻击方额外多 `N-1` 帧优势，因为对手的受身硬直从第 N 帧才开始计算，而攻击方的后摇从第 1 帧就开始了。最后一帧命中偷帧最多（`+A-1`），即完美 meaty。

```
击倒优势 = K 帧
后续动作：前摇 S 帧，持续 A 帧
持续帧窗口：[S, S+A-1]

meaty 条件：S <= K <= S+A-1
命中持续帧第 N 帧：N = K - S + 1，额外偷帧 = N - 1
完美 meaty：K = S+A-1（最后一帧命中，偷帧 A-1 帧）
```

序列结构：默认**第一个动作必须是移动动作**（Drive Rush 或前冲 66），中间可以插入任意动作消耗帧数，**最后一个动作必须是打击动作**。可以用 `--first any` 放开第一个动作的限制。

## 安装

无依赖，仅需 Python 3.10+。

## 使用

### 第一步：获取角色数据

```bash
# 查看所有可用角色
python fetch_data.py --list

# 获取指定角色数据（缓存到 data/ 目录）
python fetch_data.py Ryu
python fetch_data.py "Chun-Li"

# 强制重新下载（更新数据）
python fetch_data.py Ryu --update
```

### 第二步：计算 meaty 方案

```bash
# 列出所有 meaty 组合
python calc_meaty.py Ryu

# 只显示完美 meaty（最后一帧命中，标记 ★）
python calc_meaty.py Ryu --perfect-only

# 指定击倒来源（默认 both）
python calc_meaty.py Ryu --hit-type normal   # 普通命中击倒
python calc_meaty.py Ryu --hit-type pc       # 惩罚反击（Punish Counter）击倒

# 指定击倒类型（默认 both）
python calc_meaty.py Ryu --kd-type kd        # 普通击倒
python calc_meaty.py Ryu --kd-type hkd       # 硬击倒（对手无法后滚）

# 序列中前置动作数量上限（默认 2）
python calc_meaty.py Ryu --max-prefix 1

# 第一个动作的限制（默认 move：只能是 Drive Rush 或前冲 66）
python calc_meaty.py Ryu --first any    # 放开限制，允许任意动作开头

# 安全过滤（默认开启，去掉 on block <= -4 的收尾动作）
python calc_meaty.py Ryu --no-safe

# 额外前冲帧数（在序列之外额外计入，一般不需要）
python calc_meaty.py Ryu --dash 22
```

### 输出示例

```
KD Move : Shoulder Throw (LPLK)  [NORMAL] KD +17
  Sequence                                 K'    S    A    Hit frame    Stolen   Total adv  On block   Perfect?
  ---------------------------------------- ----- ---- ---- ------------ -------- ---------- ---------- --------
  MPMK → 8HK                               17    10   8    8/8          +7       +13        -2         ★
  MPMK → 214LP                             17    12   6    6/6          +5       +10        +2         ★
```

- **K'**：经过前置动作后剩余的击倒优势帧数
- **S**：最后动作的前摇帧数
- **A**：最后动作的持续帧数
- **Hit frame**：命中发生在第几个持续帧（`n/A`）
- **Stolen**：实际偷取的帧数（`N-1`），★ 表示完美 meaty
- **Total adv**：meaty 命中后的实际帧优势（`onHit + Stolen`）；若该动作本身会击倒对手则显示 `KD`
- **On block**：该动作被防住时的帧优势（负数表示不利）

## 角色列表（29名）

A.K.I. / Akuma / Alex / Blanka / C.Viper / Cammy / Chun-Li / Dee Jay / Dhalsim / E.Honda / Ed / Elena / Guile / Jamie / JP / Juri / Ken / Kimberly / Lily / Luke / M.Bison / Mai / Manon / Marisa / Rashid / Ryu / Sagat / Terry / Zangief

## 文件结构

```
meaty-calc/
├── fetch_data.py   # 获取并缓存角色帧数据
├── calc_meaty.py   # 计算 meaty 方案
├── data/           # 缓存的角色数据（自动生成）
│   ├── sf6framedata.json   # 完整数据源
│   └── ryu.json, chun-li.json, ...
└── README.md
```
