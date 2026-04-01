import { t } from "../i18n.js";
import { calcMeatys } from "./calculator.js";
import { ensureCharData, createMeatyState, loadData } from "./data.js";
import { extractMoves } from "./parser.js";
import { renderCharSelect, renderKdMoveSelect, renderResults } from "./renderer.js";

const state = createMeatyState();

async function loadDataAndInitUi() {
    const statusEl = document.getElementById("status");
    try {
        await loadData(state, async () => {
            renderCharSelect(state);
            const sel = document.getElementById("charSelect");
            const ryuIdx = state.charList.indexOf("Ryu");
            if (ryuIdx >= 0) sel.selectedIndex = ryuIdx;

            const selected = sel.value || state.charList[0];
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
        kdMoveFilter: document.getElementById("kdMoveSelect").value || null,
        hitTypeFilter: document.getElementById("hitType").value,
        maxPrefix: parseInt(document.getElementById("maxPrefix").value),
        safeOnly: document.getElementById("safeOnly").checked,
        cancelOnly: document.getElementById("cancelOnly").checked,
        noSpKd: document.getElementById("noSpKd").checked,
        firstAny: document.getElementById("firstAny").checked,
        minAdv: parseInt(document.getElementById("minAdv").value) || -99,
        maxDelay: parseInt(document.getElementById("maxDelay").value) || 0,
    };

    const statusEl = document.getElementById("status");
    statusEl.textContent = t("status_calculating");
    statusEl.dataset.state = "calculating";

    setTimeout(() => {
        const results = calcMeatys(moves, opts);
        state.lastResults = { list: results, total: results.length };
        statusEl.dataset.state = "result";
        renderResults(state, results);
    }, 10);
}

export function refreshForLanguage() {
    if (!state.charList.length) return;

    renderCharSelect(state);
    const charName = document.getElementById("charSelect").value;
    renderKdMoveSelect(state, charName);

    const statusEl = document.getElementById("status");
    if (statusEl.dataset.state === "result") {
        if (state.lastResults) {
            statusEl.textContent = t("status_result", charName, state.lastResults.total);
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

export async function initMeaty() {
    document.getElementById("calcBtn").addEventListener("click", calculate);
    document.getElementById("effectiveOnly").addEventListener("change", () => {
        if (state.lastResults) renderResults(state, state.lastResults.list);
    });
    document.getElementById("charSelect").addEventListener("change", async () => {
        state.lastResults = null;
        state.currentCharData = await ensureCharData(state, document.getElementById("charSelect").value);
        renderKdMoveSelect(state, document.getElementById("charSelect").value);
        await calculate();
    });

    initResultToggle();
    await loadDataAndInitUi();
    await calculate();
}
