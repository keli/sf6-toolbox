# SF6 Toolbox

`SF6 Toolbox` 是一个离线网页工具集，目前包含：
- `Frame Kill / Meaty` 计算器
- `ELO` 胜率计算器

数据基线来自 FAT：
- <https://github.com/D4RKONION/FAT>
- 具体源文件：`src/js/constants/framedata/SF6FrameData.json`

## 使用

在项目根目录启动本地静态服务器（需要通过 HTTP 读取 JSON）：

```bash
python3 -m http.server
# 然后访问 http://localhost:8000
```

页面支持中英文切换。

## 数据加载方式

前端读取顺序：
1. 先读取 `data/characters.index.json`
2. 再按索引中的 `file` 字段逐角色读取（默认是 `data/<角色目录>/final.json`）

数据文件约定：
- `fat.json`：按角色拆分后的 FAT 原始来源数据（含 `normalized` 字段）
- `overrides.json`：人工/AI 校对后的覆盖项
- `final.json`：前端实际使用的数据（由 apply 脚本生成）
- `official.json`：官网 frame 页面解析后的原始结构化结果

## Meaty 计算器

### 术语约定（和代码一致）

- `startup (U)`：首个可命中帧序号（不是“启动总帧数”）
- `active (A)`：持续帧数
- `K`：击倒优势减去前置动作和延迟后的剩余帧
- `K1 = K + 1`：起身对应到我方动作时间线的帧序号

可命中窗口：`[U, U + A - 1]`

### 命中判定与偷帧规则

1. 真 meaty（起身落在持续帧内）
- 条件：`U <= K1 <= U + A - 1`
- 命中持续帧序号：`N = K1 - U + 1`
- 偷帧：`N - 1`

2. 非 meaty 但保留 3F 反击安全窗口
- 条件：`K1 < U` 且 `U - K1 <= 3`
- 视为命中第 1 持续帧，偷帧为 `0`

3. 其他情况过滤
- `K1 > U + A - 1`（起身太晚）
- `K1 < U` 且 `U - K1 > 3`（会被 3F 反击抢先）

### 额外规则（当前实现）

- 只有 `normal` 类型收尾动作可以从“晚命中”获得偷帧收益；非 normal 收尾动作偷帧固定为 `0`
- 若最后一个前置动作是 `DR`，且收尾动作是 `normal`，则额外加 `+4`（同时作用于 `onHit` 和 `onBlock`）
- 以 `7/8/9` 开头的空中输入不会作为 meaty 收尾候选
- `OD` 收尾动作默认不参与 meaty 收尾候选

### 过滤项说明

- 击倒来源：全部 / 普通命中 / Punish Counter
- 击倒动作筛选：可指定某个 KD 动作
- 前置动作上限：`maxPrefix`（1~3）
- 最大延迟帧：`maxDelay`
- `Safe Only`：仅保留 `onBlock >= -3` 的收尾动作
- `Cancelable Moves Only`：收尾动作必须可 cancel（`cancelTypes.length > 0`）
- `Exclude Cancelable Knockdown Sources`：排除可被 special cancel 的击倒来源（`noSpKd`，即 KD 动作 `cancelTypes` 含 `sp`）
- `Allow Normals as Prefix`：允许第一个前置动作使用攻击动作
- `Allow Drive Rush as Prefix`：允许把 `DR` 作为前置动作
- `Effective Frame-Kill Only`：仅展示“有效方案”（命中后可解锁更快中重拳脚，或防住后由非正变正）

### 结果列说明

- `Sequence`：前置动作序列 + 收尾动作（前置动作附带总帧）
- `Startup` / `Active`：收尾动作的 `U` / `A`
- `Hit Frame`：命中在第几持续帧（`N/A`）
- `Stolen`：偷到的帧数（`+N-1`）
- `On Hit`：显示 `H/C/PC` 三档优势（普通命中 / Counter / Punish Counter）
- `On Block`：防住后的帧优势

## ELO 计算器

根据双方 MR（ELO）计算：
- 单局胜率
- 单盘（SF6 BO3 rounds）胜率
- 指定 BO（整场）胜率

## 数据流水线

### 1) 从 FAT 基线重建角色数据

```bash
python3 build_character_data.py normalize
```

作用：
- 读取 `data/sf6framedata.json`
- 重建 `data/<角色目录>/fat.json`
- 重建 `data/characters.index.json`
- 写入 `normalized` 字段（`startup/active/recovery/onHit/onBlock/onPC`）

如果要先在线下载最新 FAT 基线：

```bash
python3 build_character_data.py normalize --download-base
```

### 2) 生成 final.json（应用或跳过 overrides）

```bash
python3 apply_character_overrides.py
```

默认行为：
- 复制 `fatFile -> file`（通常是 `fat.json -> final.json`）
- 跳过所有 overrides

常用参数：
- `--use-overrides`：启用 `overridesFile` 覆盖逻辑
- `--apply-base fat|final`：启用 overrides 时，指定覆盖基底（默认 `fat`）
- `--copy-fat-only`：强制仅复制 FAT，忽略 overrides（优先级最高）
- `--strict`：严格校验覆盖值格式（仅允许索引友好值）

### 3) 从官网 frame 页面重建 overrides（推荐）

```bash
python3 build_official_overrides.py
```

作用：
- 从 `https://www.streetfighter.com/6/character` 读取角色 slug
- 抓取并解析 `.../character/{slug}/frame`
- 生成每个角色的 `official.json`
- 对比 FAT 后重建 `overrides.json`
- 生成冲突 CSV：
  - 角色级：`data/<角色目录>/official.conflicts.csv`
  - 汇总：`data/official_overrides.conflicts.csv`

缓存行为：
- 默认复用 `data/.official_frame_html/*.frame.html`
- 传 `--refresh` 强制重新抓取网页

常用参数：
- `--chars Ryu,Ken`：仅处理指定角色（名称取自 `characters.index.json`）
- `--allow-opaque-hitblock`：允许把 `D` 这类非数字的 `onHit/onBlock` 写入 overrides
- `--timeout 40`：设置网络超时秒数

## 目录结构

```text
sf6-toolbox/
├── index.html
├── js/
├── data/
│   ├── sf6framedata.json
│   ├── characters.index.json
│   ├── official_overrides.conflicts.csv
│   └── <Character>/
│       ├── fat.json
│       ├── final.json
│       ├── overrides.json
│       ├── official.json
│       └── official.conflicts.csv
├── build_character_data.py
├── build_official_overrides.py
├── apply_character_overrides.py
└── README.md
```
