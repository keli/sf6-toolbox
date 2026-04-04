function tryMeaty(
  kdMove,
  kdInfo,
  prefix,
  K,
  delay,
  meaty,
  results,
  nonLightMoves,
  opts,
) {
  const U = meaty.startup;
  const A = meaty.active;
  const SAFE_CHALLENGE_STARTUP_FRAMES = 3;
  const isDrLastPrefix = prefix[prefix.length - 1]?.cmd === "DR";
  if (isDrLastPrefix && moveNeedsCharge(meaty)) return;
  const drBonus = isDrLastPrefix && meaty.moveType === "normal" ? 4 : 0;
  let activeFrameHit = null;
  let stolen = 0;

  // Wake-up happens during our active frames => true meaty, can steal frames.
  const K1 = K + 1;
  if (U <= K1 && K1 <= U + A - 1) {
    activeFrameHit = K1 - U + 1;
    stolen = activeFrameHit - 1;
  } else if (K1 < U) {
    // Wake-up already happened before our first active frame.
    // Keep only options that still hit before (or trade with) a 3f challenge.
    const gapToFirstActive = U - K1;
    if (gapToFirstActive > SAFE_CHALLENGE_STARTUP_FRAMES) return;
    activeFrameHit = 1;
    stolen = 0;
  } else {
    return;
  }

  let totalAdv = null;
  if (!meaty.knockdowns.length && meaty.onHit != null) {
    totalAdv = meaty.onHit + drBonus + stolen;
  }
  const totalBlock =
    meaty.onBlock != null ? meaty.onBlock + drBonus + stolen : null;

  const unlockedMoves =
    totalAdv != null && meaty.onHit != null
      ? nonLightMoves
          .filter(
            (m) => meaty.onHit + 1 < m.startup && totalAdv + 1 >= m.startup,
          )
          .sort(
            (a, b) =>
              (b.dmg ?? -1) - (a.dmg ?? -1) ||
              a.startup - b.startup ||
              a.cmd.localeCompare(b.cmd),
          )
      : [];
  const onHitFlipped = unlockedMoves.length > 0;

  results.push({
    kdMove,
    kdInfo,
    prefix,
    meaty,
    K,
    delay,
    activeFrameHit,
    totalAdv,
    totalBlock,
    onHitFlipped,
    unlockedMoves,
  });
}

function moveHasBombTag(move) {
  return (
    /\(bomb\)/i.test(String(move?.cmd || "")) ||
    /\(bomb\)/i.test(String(move?.name || ""))
  );
}

function moveIsSuperOrCA(move) {
  const name = String(move?.name || "");
  const cmd = String(move?.cmd || "");
  return (
    /super art|critical art|\(ca\)/i.test(name) || /236236|214214/.test(cmd)
  );
}

function moveNeedsCharge(move) {
  const cmd = String(move?.cmd || "").trim();
  // Numpad charge motions, e.g. 46P / 28K and directional variants.
  return /^(?:[124]6|[123]8)/.test(cmd);
}

const CHARACTER_FILTER_RULES = {
  "M.Bison": {
    consumeBombAfterBombKd: true,
    consumeBombAfterSuperKd: true,
    consumeBombAfterKdCmdPrefixes: [
      "46PP",
      "236KK",
      "46LP",
      "46MP",
      "46HP",
      "214PP",
    ],
  },
};

function detectCharacterRuleKey(moves, charName) {
  const explicit = String(charName || "");
  if (explicit && CHARACTER_FILTER_RULES[explicit]) return explicit;

  // Fallback for stale cached UI code that does not pass charName yet.
  const hasBisonMarkers = moves.some((m) =>
    /psycho mine|psycho crusher \(bomb\)|backfist combo \(bomb\)/i.test(
      String(m?.name || ""),
    ),
  );
  return hasBisonMarkers ? "M.Bison" : "";
}

function shouldBlockBombFollowups(ruleKey, kdMove) {
  const rules = CHARACTER_FILTER_RULES[String(ruleKey || "")];
  if (!rules) return false;
  if (rules.consumeBombAfterBombKd && moveHasBombTag(kdMove)) return true;
  if (rules.consumeBombAfterSuperKd && moveIsSuperOrCA(kdMove)) return true;
  const cmd = String(kdMove?.cmd || "");
  if (
    Array.isArray(rules.consumeBombAfterKdCmdPrefixes) &&
    rules.consumeBombAfterKdCmdPrefixes.some((prefix) => cmd.startsWith(prefix))
  ) {
    return true;
  }
  return false;
}

export function calcMeatys(moves, opts) {
  const {
    kdMoveFilter,
    hitTypeFilter,
    maxPrefix,
    safeOnly,
    firstAny,
    maxDelay,
  } = opts;
  const ruleKey = detectCharacterRuleKey(moves, opts.charName);

  const meatyCandidates = moves.filter(
    (m) =>
      m.isAttack &&
      !/^[789]/.test(m.cmd) &&
      (!safeOnly || m.onBlock == null || m.onBlock >= -3) &&
      (!opts.cancelOnly || m.cancelTypes.length > 0) &&
      !m.name.startsWith("OD "),
  );
  const prefixPool = moves.filter(
    (m) =>
      m.moveType === "dash" ||
      (firstAny &&
        m.isAttack &&
        !m.isDerived &&
        !m.isThrowLike &&
        !/^[789]/.test(m.cmd) &&
        m.knockdowns.length === 0),
  );
  if (opts.includeDrPrefix) {
    prefixPool.push({
      name: "Drive Rush",
      cmd: "DR",
      startup: 11,
      active: 0,
      recovery: 0,
      total: 11,
      onBlock: null,
      onHit: null,
      moveType: "dash",
      isAttack: false,
      knockdowns: [],
    });
  }
  const firstPool = firstAny
    ? prefixPool
    : prefixPool.filter((m) => !m.isAttack);

  const nonLightMoves = moves.filter(
    (m) =>
      /^\d(MP|MK|HP|HK)$/.test(m.cmd) &&
      !/^[789]/.test(m.cmd) &&
      !m.isDerived &&
      m.startup != null,
  );

  const results = [];
  for (const kdMove of moves) {
    if (kdMoveFilter && kdMove.cmd !== kdMoveFilter) continue;
    if (kdMove.name.includes("Drive Impact")) continue;
    const blockBombFollowups = shouldBlockBombFollowups(ruleKey, kdMove);

    for (const kdInfo of kdMove.knockdowns) {
      if (hitTypeFilter !== "both" && kdInfo.hitType !== hitTypeFilter)
        continue;
      if (opts.noSpKd && kdMove.cancelTypes.includes("sp")) continue;

      const Kbase = kdInfo.advantage;
      if (Kbase <= 0) continue;

      for (const first of firstPool) {
        if (blockBombFollowups && moveHasBombTag(first)) continue;
        const Krem1 = Kbase - first.total;
        if (Krem1 <= 0) continue;

        for (const meaty of meatyCandidates) {
          if (blockBombFollowups && moveHasBombTag(meaty)) continue;
          for (let d = 0; d <= maxDelay; d++) {
            if (Krem1 - d < 0) break;
            tryMeaty(
              kdMove,
              kdInfo,
              [first],
              Krem1 - d,
              d,
              meaty,
              results,
              nonLightMoves,
              opts,
            );
          }
        }

        // DR must be the last prefix step before the meaty button.
        if (first.cmd === "DR") continue;

        if (maxPrefix >= 2) {
          for (const second of prefixPool) {
            if (blockBombFollowups && moveHasBombTag(second)) continue;
            const Krem2 = Krem1 - second.total;
            if (Krem2 <= 0) continue;

            for (const meaty of meatyCandidates) {
              if (blockBombFollowups && moveHasBombTag(meaty)) continue;
              for (let d = 0; d <= maxDelay; d++) {
                if (Krem2 - d < 0) break;
                tryMeaty(
                  kdMove,
                  kdInfo,
                  [first, second],
                  Krem2 - d,
                  d,
                  meaty,
                  results,
                  nonLightMoves,
                  opts,
                );
              }
            }

            if (maxPrefix >= 3) {
              for (const third of prefixPool) {
                if (second.cmd === "DR") continue;
                if (blockBombFollowups && moveHasBombTag(third)) continue;
                const Krem3 = Krem2 - third.total;
                if (Krem3 <= 0) continue;

                for (const meaty of meatyCandidates) {
                  if (blockBombFollowups && moveHasBombTag(meaty)) continue;
                  for (let d = 0; d <= maxDelay; d++) {
                    if (Krem3 - d < 0) break;
                    tryMeaty(
                      kdMove,
                      kdInfo,
                      [first, second, third],
                      Krem3 - d,
                      d,
                      meaty,
                      results,
                      nonLightMoves,
                      opts,
                    );
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  return results;
}
