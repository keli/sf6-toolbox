# `data/sf6framedata.json` 字段说明（FAT）

本文档说明 `data/sf6framedata.json` 的字段语义，按当前仓库（`build_character_data.py`、`js/meaty/parser.js`）与数据样本推断整理。

- 数据文件：`data/sf6framedata.json`
- 字段提取范围：
  - 角色层：`<Character>.stats.*`
  - 招式层：`<Character>.moves.<category>.<move>.*`
- 统计时间：2026-04-02

## 1) 顶层结构

```json
{
  "Ryu": {
    "moves": { ... },
    "stats": { ... }
  },
  "Ken": { ... }
}
```

- 顶层 key：角色名（如 `Ryu`、`Ken`）
- 每个角色包含：
  - `moves`：按分类分组的招式字典
  - `stats`：角色通用移动/体力等统计

## 2) `moves` 分类（category）

当前数据内出现的分类 key：

- `normal`：常规分类（普遍存在）
- `D1` / `D2` / `D3` / `D4`：Jamie 饮酒等级分表
- `Super Install`：安装类状态分表（如 Blanka/Juri/Kimberly/Guile）

## 3) 命名约定

### 3.1 常见后缀

- `...oB`：`on Block`（防御后）
- `...oH`：`on Hit`（命中后）

例如：`DRoB/DRoH`、`runStopOB/runStopOH`、`SA2oB/SA2oH`。

### 3.2 数值表示

同一字段可能是：

- 纯数字：`-3`、`8`
- 区间/括号：`"5(7)"`、`"-1~+2"`
- 文本标签：`"KD +42"`、`"Free Juggle"`、`"Crumple +67(81)"`

仓库中 `build_character_data.py` 会把 `startup/active/recovery/onHit/onBlock/onPC` 规范化到 `normalized` 子结构（在 `.fat.json` / `.json` 中）。

## 4) `stats` 字段（全集）

| 字段 | 说明 |
|---|---|
| `health` | 体力值 |
| `fWalk` | 前走速度 |
| `bWalk` | 后走速度 |
| `fDash` | 前冲总帧 |
| `fDashDist` | 前冲距离 |
| `bDash` | 后冲总帧 |
| `bDashDist` | 后冲距离 |
| `fJump` | 前跳总帧（常含分解） |
| `fJumpDist` | 前跳水平距离 |
| `bJump` | 后跳总帧（常含分解） |
| `bJumpDist` | 后跳水平距离 |
| `nJump` | 原地跳总帧 |
| `dRushDist` | Drive Rush 最短/基础推进距离 |
| `dRushDistMin` | Drive Rush 最小推进距离 |
| `dRushDistMax` | Drive Rush 最大推进距离 |
| `dRushDistBlock` | Drive Rush 在防御相关场景的推进距离统计值 |
| `throwRange` | 普通投范围 |
| `throwHurt` | 与投相关的受击/判定尺寸参数 |
| `fastestNormal` | 最快普攻启动帧（如 `4f`） |
| `bestReversal` | 角色主要无敌反击招（文本） |
| `threeLetterCode` | 角色三字母缩写 |
| `hashtag` | 标签字符串（如 `#SF6_RYU`） |
| `phrase` | 角色台词文本 |
| `taunt` | 挑衅说明 |
| `color` | 角色配色标识（hex） |

## 5) `moves` 字段（全集）

下表覆盖当前 `sf6framedata.json` 内出现的全部 82 个招式字段。

### 5.1 标识与展示类

| 字段 | 说明 |
|---|---|
| `i` | 招式在该分表内的索引序号 |
| `moveName` | 招式名（完整名） |
| `cmnName` | 常用/简化名 |
| `movesList` | 招式在来源站点的分组显示名 |
| `moveType` | 招式类型（`normal`/`special`/`throw`/`drive`/`super` 等） |
| `moveMotion` | 指令类型（如 `N`、`QCF`、`F,F`） |
| `moveButton` | 对应按键描述 |
| `ezCmd` | 易读输入写法 |
| `numCmd` | 数字键位指令写法（前端优先使用） |
| `plnCmd` | 文本指令写法（`numCmd` 兜底） |
| `scKey` | 来源数据内部映射键（A.K.I. 存在） |
| `extraInfo` | 额外说明数组（自由文本） |

### 5.2 帧数据（基础）

| 字段 | 说明 |
|---|---|
| `startup` | 发生 |
| `active` | 持续 |
| `recovery` | 硬直 |
| `total` | 总帧 |
| `onBlock` | 防御后帧差 |
| `onHit` | 命中后帧差/击倒信息 |
| `onPC` | Punish Counter 后帧差/击倒信息 |
| `onPP` | Perfect Parry 后相关帧差（通常为被 PP 后） |
| `blockstun` | 对手防御硬直 |
| `hitstun` | 对手命中硬直 |
| `hitstop` | 命中停顿 |
| `fullStartup` | 多段/派生的完整发生描述 |
| `fullActive` | 多段/派生的完整持续描述 |

### 5.3 资源与伤害

| 字段 | 说明 |
|---|---|
| `dmg` | 基础伤害 |
| `fullDmg` | 多段/全段总伤害描述 |
| `dmgScaling` | 伤害补正说明 |
| `chp` | 芯片伤害（Chip） |
| `stun` | 眩晕相关数值（仅个别条目出现） |
| `DDoB` | 命中在防御时对对手 Drive 造成的伤害（Drive Damage on Block） |
| `DDoH` | 命中时对对手 Drive 造成的伤害（Drive Damage on Hit） |
| `DGain` | 自身 Drive 增减 |
| `OppSoB` | 对手在防御时获得的 SA（Super） |
| `OppSoH` | 对手在命中时获得的 SA |
| `SelfSoB` | 自身在防御时获得/消耗的 SA |
| `SelfSoH` | 自身在命中时获得/消耗的 SA |
| `ToxicBlossom` | A.K.I. 毒爆状态下的额外命中结果 |

### 5.4 机制与判定标记

| 字段 | 说明 |
|---|---|
| `atkLvl` | 攻击等级/性质（含 `T` 投技等） |
| `range` | 招式触及距离/作用距离 |
| `projectile` | 是否飞行道具相关 |
| `airmove` | 是否空中招式 |
| `antiAirMove` | 是否标记为对空用途 |
| `followUp` | 是否派生/后续动作条目 |
| `nonHittingMove` | 是否非打击动作（如纯位移/姿态） |
| `chargeDirection` | 蓄力方向（如 `B`、`D`、`R`） |
| `xx` | 可取消链路标签数组（如 `ch`/`sp`/`su`/`tc`） |
| `jugStart` | Juggle 起始值 |
| `jugIncr` | Juggle 递增值 |
| `jugLimit` | Juggle 上限 |
| `noHL` | Jamie 分表中的内部标记字段（仅 Jamie 出现） |

### 5.5 特殊状态/派生帧差字段（角色特有）

这些字段都属于“某个状态下的 onBlock/onHit 衍生值”，字段名通常由状态简称 + `oB/oH` 组成。

| 字段 | 说明 | 主要角色 |
|---|---|---|
| `DRoB` / `DRoH` | Drive Rush 强化后帧差 | 多角色 |
| `afterDRoB` / `afterDRoH` | DR 后续特定分支帧差 | Akuma/Cammy/Dee Jay/Jamie/Kimberly/Zangief |
| `CCoB` / `CCoH` | Coward Crouch 相关分支帧差 | Blanka |
| `SSoB` / `SSoH` | SS 姿态分支帧差（如 Serenity Stream/Snake Stance） | Chun-Li/A.K.I. |
| `SA2oB` / `SA2oH` | SA2 安装/强化状态下帧差 | Blanka/Guile/Jamie/JP/Juri |
| `StanceOB` / `StanceOH` | 通用姿态分支帧差 | Alex |
| `runStopOB` / `runStopOH` | 跑步急停相关帧差 | Ken/Kimberly |
| `drinkOB` / `drinkOH` | Jamie 饮酒状态帧差 | Jamie |
| `duckOB` / `duckOH` | Ducking 状态分支帧差 | Ed |
| `FeintOB` / `FeintOH` | Feint 分支帧差 | C.Viper |
| `FFdashOB` / `FFdashOH` | Fast/Follow dash 分支帧差 | C.Viper |
| `hopOB` / `hopOH` | Hop 分支帧差 | Blanka |
| `SlasherOB` / `SlasherOH` | Slasher 分支帧差 | Dee Jay |
| `SobatOB` / `SobatOH` | Sobat 分支帧差 | Dee Jay |

### 5.6 命中确认窗口字段

| 字段 | 说明 |
|---|---|
| `hcWinTc` | Target Combo 的确认窗口 |
| `hcWinSpCa` | Special/CA 相关确认窗口 |
| `hcWinNotes` | 确认窗口补充说明 |

## 6) 哪些字段被当前前端核心逻辑直接消费

以 `js/meaty/parser.js` 为准，Meaty 计算器核心直接读取/依赖这些字段：

- `moveName` / `numCmd` / `plnCmd`
- `startup` / `active` / `recovery` / `total`
- `onBlock` / `onHit` / `onPC`
- `atkLvl` / `moveType` / `xx`
- `dmg`
- `stats.fDash`

其余字段主要用于展示、注释、资源计算或角色特定分支信息。

## 7) 备注

- FAT 原始字段并非严格统一 schema：同一字段可能是数字、字符串、区间文本或描述文本。
- 本文档中“角色特有分支字段”是按当前数据出现情况归纳，未来 FAT 更新可能新增同类字段。
- 若要做机器可校验 schema，建议在本仓库基于 `normalized` 结构再派生一层严格类型化模型。
