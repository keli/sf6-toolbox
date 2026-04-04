import { t } from "../i18n.js";
import { calcMeatys } from "./calculator.js";
import { ensureCharData, createMeatyState, loadData } from "./data.js";
import { extractMoves } from "./parser.js";
import {
  renderCharSelect,
  renderKdMoveSelect,
  renderResults,
} from "./renderer.js";

const state = createMeatyState();
const LAST_CHAR_KEY = "meaty:lastChar";
let autoCalcDebounceTimer = null;

const DEFAULT_OPTS = {
  kdMove: "",
  hitType: "both",
  maxPrefix: "2",
  maxDelay: "0",
  safeOnly: true,
  cancelOnly: true,
  noSpKd: true,
  firstAny: false,
  includeDrFirst: false,
  effectiveOnly: true,
};

function applyDefaultOptions() {
  document.getElementById("kdMoveSelect").value = DEFAULT_OPTS.kdMove;
  document.getElementById("hitType").value = DEFAULT_OPTS.hitType;
  document.getElementById("maxPrefix").value = DEFAULT_OPTS.maxPrefix;
  document.getElementById("maxDelay").value = DEFAULT_OPTS.maxDelay;
  document.getElementById("safeOnly").checked = DEFAULT_OPTS.safeOnly;
  document.getElementById("cancelOnly").checked = DEFAULT_OPTS.cancelOnly;
  document.getElementById("noSpKd").checked = DEFAULT_OPTS.noSpKd;
  document.getElementById("firstAny").checked = DEFAULT_OPTS.firstAny;
  document.getElementById("includeDrFirst").checked =
    DEFAULT_OPTS.includeDrFirst;
  document.getElementById("effectiveOnly").checked = DEFAULT_OPTS.effectiveOnly;
}

async function loadDataAndInitUi() {
  const statusEl = document.getElementById("status");
  try {
    await loadData(state, async () => {
      renderCharSelect(state);
      const sel = document.getElementById("charSelect");
      const savedChar = localStorage.getItem(LAST_CHAR_KEY);
      const ryuIdx = state.charList.indexOf("Ryu");
      if (savedChar && state.charList.includes(savedChar)) {
        sel.value = savedChar;
      } else if (ryuIdx >= 0) {
        sel.selectedIndex = ryuIdx;
      }

      const selected = sel.value || state.charList[0];
      localStorage.setItem(LAST_CHAR_KEY, selected);
      state.currentCharData = await ensureCharData(state, selected);
      renderKdMoveSelect(state, selected);
    });

    document.getElementById("calcBtn").disabled = false;
    statusEl.textContent = t("status_loaded", state.charList.length);
    statusEl.dataset.state = "loaded";
  } catch (e) {
    statusEl.textContent = t("status_failed", e.message);
    statusEl.dataset.state = "error";
  }
}

export async function calculate() {
  const charName = document.getElementById("charSelect").value;
  const charData = await ensureCharData(state, charName);
  state.currentCharData = charData;
  if (!charData) return;

  const moves = extractMoves(charData);
  const opts = {
    charName,
    kdMoveFilter: document.getElementById("kdMoveSelect").value || null,
    hitTypeFilter: document.getElementById("hitType").value,
    maxPrefix: parseInt(document.getElementById("maxPrefix").value),
    safeOnly: document.getElementById("safeOnly").checked,
    cancelOnly: document.getElementById("cancelOnly").checked,
    noSpKd: document.getElementById("noSpKd").checked,
    firstAny: document.getElementById("firstAny").checked,
    includeDrPrefix: document.getElementById("includeDrFirst").checked,
    maxDelay: parseInt(document.getElementById("maxDelay").value) || 0,
  };

  const statusEl = document.getElementById("status");
  statusEl.textContent = t("status_calculating");
  statusEl.dataset.state = "calculating";
  const results = calcMeatys(moves, opts);
  state.lastResults = { list: results, total: results.length };
  statusEl.dataset.state = "result";
  renderResults(state, results);
}

export function refreshForLanguage() {
  if (!state.charList.length) return;

  renderCharSelect(state);
  const charName = document.getElementById("charSelect").value;
  renderKdMoveSelect(state, charName);

  const statusEl = document.getElementById("status");
  if (statusEl.dataset.state === "result") {
    if (state.lastResults) {
      statusEl.textContent = t(
        "status_result",
        charName,
        state.lastResults.total,
      );
    }
  } else if (statusEl.dataset.state === "loaded") {
    statusEl.textContent = t("status_loaded", state.charList.length);
  }

  if (state.lastResults) renderResults(state, state.lastResults.list);
}

function initResultToggle() {
  document.getElementById("meaty-results").addEventListener("click", (e) => {
    const header = e.target.closest(".kd-header");
    if (!header) return;
    const group = header.closest(".kd-group");
    if (group) group.classList.toggle("collapsed");
  });
}

async function resetOptions() {
  applyDefaultOptions();
  state.lastResults = null;
  await calculate();
}

function scheduleAutoCalculate() {
  if (autoCalcDebounceTimer != null) {
    clearTimeout(autoCalcDebounceTimer);
  }
  autoCalcDebounceTimer = setTimeout(() => {
    autoCalcDebounceTimer = null;
    void calculate();
  }, 60);
}

export async function initMeaty() {
  document.getElementById("calcBtn").addEventListener("click", calculate);
  document.getElementById("resetBtn").addEventListener("click", resetOptions);
  document.getElementById("charSelect").addEventListener("change", async () => {
    const charName = document.getElementById("charSelect").value;
    localStorage.setItem(LAST_CHAR_KEY, charName);
    state.lastResults = null;
    state.currentCharData = await ensureCharData(state, charName);
    renderKdMoveSelect(state, charName);
    await calculate();
  });
  const autoCalcOnChangeIds = [
    "kdMoveSelect",
    "hitType",
    "maxPrefix",
    "safeOnly",
    "cancelOnly",
    "noSpKd",
    "firstAny",
    "includeDrFirst",
    "effectiveOnly",
  ];
  autoCalcOnChangeIds.forEach((id) => {
    document
      .getElementById(id)
      .addEventListener("change", scheduleAutoCalculate);
  });
  document
    .getElementById("maxDelay")
    .addEventListener("input", scheduleAutoCalculate);
  document
    .getElementById("maxDelay")
    .addEventListener("change", scheduleAutoCalculate);

  initResultToggle();
  await loadDataAndInitUi();
  await calculate();
}
