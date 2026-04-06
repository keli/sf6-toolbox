import { t, tChar, tMove } from "../i18n.js";
import { extractMoves } from "./parser.js";

const HIT_TYPE_CLASS = {
  normal: "kd-type-normal",
  pc: "kd-type-pc",
  cc: "kd-type-cc",
};

function rowOnHitAdv(r) {
  return r.totalAdv;
}

function rowOnBlockAdv(r) {
  return r.totalBlock;
}

function fmtSeq(prefix, meaty) {
  return [...prefix.map((m) => m.cmd), meaty.cmd].join(" → ");
}

function fmtSeqWithFrames(prefix, meaty) {
  const parts = prefix.map((m) => {
    const label =
      tMove(m.name) !== m.name ? `${tMove(m.name)} (${m.cmd})` : m.cmd;
    return `${label}<span style="color:#999;font-size:0.85em">[${m.total}f]</span>`;
  });
  const meatyLabel =
    tMove(meaty.name) !== meaty.name
      ? `${tMove(meaty.name)} (${meaty.cmd})`
      : meaty.cmd;
  parts.push(meatyLabel);
  return parts.join(" → ");
}

function escapeAttr(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\n", "&#10;");
}

function startupFrameCount(move) {
  return move.startup - 1;
}

function listStealableNormals(ob, normalButtons) {
  if (ob == null) return [];
  return normalButtons
    .filter((m) => startupFrameCount(m) - ob <= 4)
    .sort(
      (a, b) =>
        (b.dmg ?? -1) - (a.dmg ?? -1) ||
        startupFrameCount(a) - startupFrameCount(b) ||
        a.cmd.localeCompare(b.cmd),
    );
}

function listBlockStealableNormals(ob, normalButtons) {
  if (ob == null || ob <= 0) return [];
  return normalButtons
    .filter((m) => startupFrameCount(m) - ob <= 4)
    .sort(
      (a, b) =>
        (b.dmg ?? -1) - (a.dmg ?? -1) ||
        startupFrameCount(a) - startupFrameCount(b) ||
        a.cmd.localeCompare(b.cmd),
    );
}

function buildNormalButtons(charData) {
  const byCmd = new Map();
  for (const m of extractMoves(charData)) {
    if (
      !(
        m.moveType === "normal" &&
        !m.isDerived &&
        !/^[789]/.test(m.cmd) &&
        /^\d(MP|MK|HP|HK)$/.test(m.cmd) &&
        m.startup != null
      )
    )
      continue;
    const prev = byCmd.get(m.cmd);
    if (
      !prev ||
      (m.dmg ?? -1) > (prev.dmg ?? -1) ||
      ((m.dmg ?? -1) === (prev.dmg ?? -1) && m.startup < prev.startup)
    ) {
      byCmd.set(m.cmd, {
        cmd: m.cmd,
        startup: m.startup,
        dmg: m.dmg ?? null,
        onBlock: m.onBlock ?? null,
      });
    }
  }
  return [...byCmd.values()];
}

function fmtBlock(ob) {
  if (ob == null) return '<span class="safe-zero">?</span>';
  const cls = ob > 0 ? "safe-plus" : ob < 0 ? "safe-minus" : "safe-zero";
  return `<span class="${cls}">${ob >= 0 ? "+" : ""}${ob}</span>`;
}

function fmtFromBase(base, rendered) {
  if (base == null) return rendered;
  const text = `${base >= 0 ? "+" : ""}${base}`;
  return `<span style="color:#888;font-size:0.9em">${text} → </span>${rendered}`;
}

function withDrDisplayBaseBonus(base, row) {
  if (base == null) return base;
  const isDrLastPrefix = row.prefix[row.prefix.length - 1]?.cmd === "DR";
  const drBonus = isDrLastPrefix && row.meaty.moveType === "normal" ? 4 : 0;
  return base + drBonus;
}

function fmtHitAdvTriplet(adv) {
  if (adv == null) return "?";
  const h = `${adv >= 0 ? "+" : ""}${adv}`;
  const c = `${adv + 2 >= 0 ? "+" : ""}${adv + 2}`;
  const pc = `${adv + 4 >= 0 ? "+" : ""}${adv + 4}`;
  return `${h}/${c}/${pc}`;
}

function fmtFollowupTag(adv, normalButtons, marker) {
  if (adv == null) return "";
  const moves = listStealableNormals(adv, normalButtons);
  if (!moves.length) return "";
  const labels = moves.map((m) => m.cmd).join("/");
  return `<span title="${escapeAttr(labels)}" style="color:#f90;font-size:0.85em;cursor:default">${marker}</span>`;
}

function fmtHitFollowupTags(adv, normalButtons) {
  if (adv == null) return "";
  const h = fmtFollowupTag(adv, normalButtons, "H");
  const c = fmtFollowupTag(adv + 2, normalButtons, "C");
  const pc = fmtFollowupTag(adv + 4, normalButtons, "PC");
  const tags = [h, c, pc].filter(Boolean);
  if (!tags.length) return "";
  return ` ${tags.join('<span style="color:#999">/</span>')}`;
}

function fmtBlockFollowupTag(ob, normalButtons, safeOnly) {
  if (ob == null || ob <= 0) return "";
  let moves = listBlockStealableNormals(ob, normalButtons);
  if (safeOnly) {
    moves = moves.filter((m) => m.onBlock == null || m.onBlock >= -3);
  }
  if (!moves.length) return "";
  const labels = moves.map((m) => m.cmd).join("/");
  return ` <span title="${escapeAttr(labels)}" style="color:#f90;font-size:0.85em;cursor:default">B</span>`;
}

export function renderCharSelect(state) {
  if (!state.charList.length) return;
  const sel = document.getElementById("charSelect");
  const current = sel.value;
  sel.innerHTML = state.charList
    .map((c) => `<option value="${c}">${tChar(c)}</option>`)
    .join("");

  if (current && state.charList.includes(current)) {
    sel.value = current;
  }
}

export function renderKdMoveSelect(state, charName) {
  const sel = document.getElementById("kdMoveSelect");
  const prev = sel.value;
  if (!state.currentCharData || !charName) {
    sel.innerHTML = `<option value="">${t("kd_move_all")}</option>`;
    return;
  }

  const moves = extractMoves(state.currentCharData);
  const kdMoves = moves.filter(
    (m) => m.knockdowns.length > 0 && !m.name.includes("Drive Impact"),
  );

  sel.innerHTML =
    `<option value="">${t("kd_move_all")}</option>` +
    kdMoves
      .map((m) => {
        const label = `${tMove(m.name)} (${m.displayCmd ?? m.cmd})`;
        return `<option value="${m.cmd}">${label}</option>`;
      })
      .join("");

  if (prev && [...sel.options].some((o) => o.value === prev)) sel.value = prev;
}

export function renderResults(state, results) {
  const el = document.getElementById("meaty-results");
  const statusEl = document.getElementById("status");
  const charName = document.getElementById("charSelect").value;
  const singleKdMoveSelected = Boolean(
    document.getElementById("kdMoveSelect").value,
  );

  const effectiveOnly = document.getElementById("effectiveOnly").checked;
  const safeOnly = document.getElementById("safeOnly").checked;
  const onBlockFlipped = (r) =>
    r.meaty.onBlock != null && r.meaty.onBlock <= 0 && rowOnBlockAdv(r) > 0;
  if (effectiveOnly)
    results = results.filter((r) => r.onHitFlipped || onBlockFlipped(r));

  if (!results.length) {
    if (statusEl.dataset.state === "result" && state.lastResults) {
      statusEl.textContent = t("status_result", charName, 0);
    }
    el.innerHTML = `<div class="no-results">${t("no_results")}</div>`;
    return;
  }

  const normalButtons = buildNormalButtons(state.currentCharData);

  const groups = new Map();
  for (const r of results) {
    // Merge normal/PC variants when they share the same KD move + KD properties.
    const moveKey = `${r.kdMove.name}|${r.kdMove.cmd}`;
    const key = `${moveKey}|${r.kdInfo.advantageMin}|${r.kdInfo.advantageMax}|${r.kdInfo.kdType}`;
    if (!groups.has(key)) {
      groups.set(key, {
        kdInfo: r.kdInfo,
        kdTypes: new Set(),
        sources: new Map(),
        rows: [],
      });
    }
    const g = groups.get(key);
    g.kdTypes.add(r.kdInfo.kdType);
    if (!g.sources.has(moveKey)) {
      g.sources.set(moveKey, {
        move: r.kdMove,
        hitTypes: new Set(),
      });
    }
    g.sources.get(moveKey).hitTypes.add(r.kdInfo.hitType);
    g.rows.push(r);
  }

  for (const g of groups.values()) {
    const seen = new Set();
    g.rows = g.rows.filter((r) => {
      const k = `${fmtSeq(r.prefix, r.meaty)}|${r.K}|${r.delay}`;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  }

  const sorted = [...groups.values()].sort(
    (a, b) =>
      (a.rows.length > 10) - (b.rows.length > 10) ||
      b.kdInfo.advantage - a.kdInfo.advantage,
  );

  let html = "";
  let visibleCount = 0;

  for (const { kdInfo, kdTypes, sources, rows } of sorted) {
    const srcHtml = [...sources.values()]
      .map(({ move, hitTypes }) => {
        const tags = [...hitTypes]
          .sort()
          .map(
            (ht) =>
              `<span class="${HIT_TYPE_CLASS[ht] || ""}">[${t(`hit_type_${ht}`) || ht}]</span>`,
          )
          .join("");
        const moveName = tMove(move.name);
        return `${moveName} <span style="color:#666">(${move.displayCmd ?? move.cmd})</span> ${tags}`;
      })
      .join('<span style="color:#555"> / </span>');

    const collapsed =
      !singleKdMoveSelected && rows.length > 10 ? " collapsed" : "";
    html += `<div class="kd-group${collapsed}">`;
    html += `<div class="kd-header">${srcHtml} `;

    const kdTypeLabel =
      kdTypes.size > 1 ? [...kdTypes].sort().join("/") : kdInfo.kdType;
    const kdAdvText =
      typeof kdInfo.advantageMax === "number" &&
      kdInfo.advantageMax !== kdInfo.advantageMin
        ? `${kdTypeLabel} +${kdInfo.advantageMin}~${kdInfo.advantageMax}`
        : `${kdTypeLabel} +${kdInfo.advantageMin ?? kdInfo.advantage}`;
    html += `<span class="kd-adv">${kdAdvText}</span></div>`;

    html += '<div class="kd-body"><table><thead><tr>';
    html += `<th>${t("th_sequence")}</th><th>${t("th_startup")}</th><th>${t("th_active")}</th><th>${t("th_hit_frame")}</th><th>${t("th_stolen")}</th><th>${t("th_on_hit")}</th><th>${t("th_on_block")}</th>`;
    html += "</tr></thead><tbody>";

    function seqPriority(r) {
      const cmd = r.meaty.cmd;
      if (/^\d(HP|HK)$/.test(cmd)) return 0;
      if (/^\d(MP|MK)$/.test(cmd)) return 1;
      if (/^\d(LP|LK)$/.test(cmd)) return 2;
      return 3;
    }

    const sortedRows = rows.sort(
      (a, b) =>
        seqPriority(a) - seqPriority(b) ||
        b.activeFrameHit - a.activeFrameHit ||
        a.prefix.length - b.prefix.length,
    );

    visibleCount += sortedRows.length;
    for (const r of sortedRows) {
      const stolen =
        typeof r.stolen === "number" ? r.stolen : r.activeFrameHit - 1;
      const hitAdv = rowOnHitAdv(r);
      const blockAdv = rowOnBlockAdv(r);
      const showDelta = stolen > 0;

      const hitTriplet =
        hitAdv != null
          ? `<span class="total-adv">${fmtHitAdvTriplet(hitAdv)}</span>`
          : "?";
      const hitDisplay = showDelta
        ? fmtFromBase(withDrDisplayBaseBonus(r.meaty.onHit, r), hitTriplet)
        : hitTriplet;
      const blockDisplay = showDelta
        ? fmtFromBase(
            withDrDisplayBaseBonus(r.meaty.onBlock, r),
            fmtBlock(blockAdv),
          )
        : fmtBlock(blockAdv);

      const totalStr = r.meaty.knockdowns.length
        ? `<span class="kd-adv-cell">${t(r.kdInfo.kdType === "HKD" ? "hkd_label" : "kd_label")}</span>`
        : hitAdv != null
          ? `${hitDisplay}${fmtHitFollowupTags(hitAdv, normalButtons)}`
          : "?";

      const delayStr =
        r.delay > 0
          ? ` <span style="color:#f90;font-size:0.85em">~${r.delay}f</span>`
          : "";
      const canDelay = r.meaty.active - r.activeFrameHit;
      const canShowDelayHint = r.meaty.moveType === "normal";
      const canDelayStr =
        canShowDelayHint && canDelay > 0
          ? ` <span title="${t("tip_can_delay", canDelay)}" style="color:#888;font-size:0.85em;cursor:default">↓${canDelay}f</span>`
          : "";

      html += "<tr>";
      html += `<td>${fmtSeqWithFrames(r.prefix, r.meaty)}${delayStr}</td>`;
      html += `<td>${r.meaty.startup}</td>`;
      html += `<td>${r.meaty.active}</td>`;
      html += `<td>${r.activeFrameHit}/${r.meaty.active}${canDelayStr}</td>`;
      html += `<td><span class="stolen">+${stolen}</span></td>`;
      html += `<td>${totalStr}</td>`;
      html += `<td>${blockDisplay}${fmtBlockFollowupTag(blockAdv, normalButtons, safeOnly)}</td>`;
      html += "</tr>";
    }

    html += "</tbody></table></div></div>";
  }

  if (statusEl.dataset.state === "result" && state.lastResults) {
    statusEl.textContent = t("status_result", charName, visibleCount);
  }
  el.innerHTML = html;
}
