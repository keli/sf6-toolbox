export const STRINGS = {
  en: {
    tab_meaty: "Meaty Calculator",
    tab_elo: "ELO Win Rate",
    lbl_character: "Character",
    lbl_kd_move: "Knockdown move",
    kd_move_all: "All",
    lbl_hit_type: "Hit type",
    lbl_max_prefix: "Max prefix moves",
    lbl_max_delay: "Max delay (frames) ⚠",
    note_delay: "⚠ Delayed setups are theoretical values only.",
    chk_safe_only: "Safe only (on block ≥ −3)",
    chk_cancel_only: "Cancelable only",
    chk_no_sp_kd: "Exclude cancelable KD sources",
    chk_first_any: "Allow normals as prefix",
    chk_include_dr_first: "Allow DR as prefix",
    chk_effective_only: "Effective meaty only",
    btn_calculate: "Calculate",
    btn_reset: "Reset filters",
    loading: "Loading…",
    status_loading: "Loading data…",
    status_loaded: (n) => `Loaded ${n} characters.`,
    status_failed: (msg) => `Failed to load data: ${msg}`,
    status_calculating: "Calculating…",
    status_result: (char, n) => `${char}: ${n} setups found`,
    no_results: "No setups found for the current filters.",
    th_sequence: "Sequence",
    th_startup: "Startup",
    th_active: "Active",
    th_hit_frame: "Hit frame",
    th_stolen: "Late",
    th_on_hit: "On hit",
    th_on_block: "On block",
    tip_block_flip: "Originally negative on block",
    tip_block_stealable: "Stealable normals: ",
    tip_none: "None",
    tip_can_delay: (n) =>
      `Delay ${n}f — may or may not result in optimal hit frame (some moves have fewer active frames when not done ASAP)`,
    kd_label: "KD",
    hkd_label: "HKD",
    hit_type_normal: "Normal",
    hit_type_pc: "PC",
    hit_all: "All",
    hit_normal: "Normal hit",
    hit_pc: "Punish counter (PC)",
    elo_subtitle: "Win probability calculator based on ELO ratings",
    player_a: "Player A",
    player_b: "Player B",
    lbl_mr: "Master Rating (MR)",
    lbl_match_format: "Match format (Best of)",
    elo_round_winrate: "Win rate per round",
    elo_set_winrate: "Win rate per set (SF6 BO3)",
    elo_match_winrate: (n) => `Match win rate (BO${n})`,
    elo_info_html:
      "<strong>Note:</strong> In SF6, each set is best-of-3 rounds. This calculator uses ELO ratings to compute per-round win probability, then derives per-set and per-match probabilities.",
  },
  zh: {
    tab_meaty: "偷帧计算器",
    tab_elo: "ELO 胜率",
    lbl_character: "角色",
    lbl_kd_move: "击倒技",
    kd_move_all: "全部",
    lbl_hit_type: "命中类型",
    lbl_max_prefix: "前置技最多数量",
    lbl_max_delay: "最大放帧数 ⚠",
    note_delay: "⚠ 放帧方案为理论数值。",
    chk_safe_only: "仅安全技（防御后 ≥ −3）",
    chk_cancel_only: "仅可取消技",
    chk_no_sp_kd: "排除可取消击倒源",
    chk_first_any: "允许普通技作为前置",
    chk_include_dr_first: "允许绿冲作为前置",
    chk_effective_only: "有效偷帧",
    btn_calculate: "计算",
    btn_reset: "重置筛选",
    loading: "加载中…",
    status_loading: "正在加载数据…",
    status_loaded: (n) => `已加载 ${n} 个角色。`,
    status_failed: (msg) => `数据加载失败：${msg}`,
    status_calculating: "计算中…",
    status_result: (char, n) => `${char}：找到 ${n} 个偷帧方案`,
    no_results: "当前过滤条件下未找到任何方案。",
    th_sequence: "连段",
    th_startup: "发生",
    th_active: "持续",
    th_hit_frame: "命中帧",
    th_stolen: "偷帧数",
    th_on_hit: "命中",
    th_on_block: "防御",
    tip_block_flip: "原本防御后为负",
    tip_block_stealable: "可抢普通拳脚：",
    tip_none: "无",
    tip_can_delay: (n) =>
      `放 ${n} 帧可能达到最优命中（部分招式非最速时持续帧会缩短，实际帧数可能更差）`,
    kd_label: "倒地",
    hkd_label: "硬倒地",
    hit_type_normal: "普通",
    hit_type_pc: "确反康",
    hit_all: "全部",
    hit_normal: "普通命中",
    hit_pc: "确反康 (PC)",
    elo_subtitle: "基于 ELO 评分的胜率计算器",
    player_a: "玩家 A",
    player_b: "玩家 B",
    lbl_mr: "Master Rating (MR)",
    lbl_match_format: "赛制（BO）",
    elo_round_winrate: "单局胜率",
    elo_set_winrate: "单 Set 胜率（SF6 BO3）",
    elo_match_winrate: (n) => `比赛胜率（BO${n}）`,
    elo_info_html:
      "<strong>说明：</strong>SF6 中每个 Set 为 3 局 2 胜制。本计算器利用 ELO 评分计算单局胜率，再推导出 Set 胜率与比赛胜率。",
  },
};

const savedLang = localStorage.getItem("lang");
const browserLang = navigator.language || "";
let currentLang = savedLang || (browserLang.startsWith("zh") ? "zh" : "en");

const dataTranslations = {};

const MOVE_PREFIX_ZH = [
  ["Drive Impact: ", "斗气迸放："],
  ["Drive Reversal: ", "斗气反击："],
];

export function getCurrentLang() {
  return currentLang;
}

export function t(key, ...args) {
  const val = STRINGS[currentLang][key];
  if (typeof val === "function") return val(...args);
  return val ?? key;
}

export function tChar(name) {
  if (currentLang === "en") return name;
  return dataTranslations[currentLang]?.charNames?.[name] || name;
}

export function tMove(name) {
  if (currentLang === "en") return name;
  const zh = dataTranslations[currentLang]?.moveNames?.[name];
  if (zh) return zh;
  for (const [en, zhPrefix] of MOVE_PREFIX_ZH) {
    if (name.startsWith(en)) return zhPrefix + name.slice(en.length);
  }
  return name;
}

export async function loadDataTranslations(lang) {
  if (lang === "en" || dataTranslations[lang]) return;
  try {
    const resp = await fetch(`data/i18n-${lang}.json`);
    dataTranslations[lang] = await resp.json();
  } catch (_e) {
    dataTranslations[lang] = {};
  }
}

export function applyLang() {
  document.documentElement.lang = currentLang;

  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const key = el.getAttribute("data-i18n");
    const val = STRINGS[currentLang][key];
    if (typeof val === "string") el.textContent = val;
  });

  document.querySelectorAll("[data-i18n-html]").forEach((el) => {
    const key = el.getAttribute("data-i18n-html");
    const val = STRINGS[currentLang][key];
    if (typeof val === "string") el.innerHTML = val;
  });

  document.querySelectorAll(".lang-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.lang === currentLang);
  });
}

export async function setLang(lang) {
  await loadDataTranslations(lang);
  currentLang = lang;
  localStorage.setItem("lang", lang);
  applyLang();
}

export async function initLang() {
  await loadDataTranslations(currentLang);
  applyLang();
}
