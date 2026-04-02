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
  const isDrLastPrefix = prefix[prefix.length - 1]?.cmd === "DR";
  const drNormalBypassStartup =
    isDrLastPrefix && meaty.moveType === "normal" && !/^[789]/.test(meaty.cmd);
  // DR -> ground normals skip startup; treat it as 1f in this timeline model.
  const S = drNormalBypassStartup ? 1 : meaty.startup;
  const A = meaty.active;
  if (S - 1 <= K && K <= S + A - 2) {
    const activeFrameHit = K - S + 2;
    const stolen = activeFrameHit - 1;
    let totalAdv = null;
    if (!meaty.knockdowns.length && meaty.onHit != null)
      totalAdv = meaty.onHit + stolen;
    const totalBlock = meaty.onBlock != null ? meaty.onBlock + stolen : null;

    if (stolen === 0) return;
    const unlockedMoves =
      totalAdv != null && meaty.onHit != null
        ? nonLightMoves
            .filter((m) => meaty.onHit < m.startup && totalAdv >= m.startup)
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
        !m.isThrowLike &&
        !/^[789]/.test(m.cmd) &&
        m.knockdowns.length === 0),
  );
  if (opts.includeDrPrefix) {
    prefixPool.push({
      name: "Drive Rush",
      cmd: "DR",
      startup: 14,
      active: 0,
      recovery: 0,
      total: 14,
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
      m.startup != null,
  );

  const results = [];
  for (const kdMove of moves) {
    if (kdMoveFilter && kdMove.cmd !== kdMoveFilter) continue;
    if (kdMove.name.includes("Drive Impact")) continue;

    for (const kdInfo of kdMove.knockdowns) {
      if (hitTypeFilter !== "both" && kdInfo.hitType !== hitTypeFilter)
        continue;
      if (opts.noSpKd && kdMove.cancelTypes.includes("sp")) continue;

      const Kbase = kdInfo.advantage;
      if (Kbase <= 0) continue;

      for (const first of firstPool) {
        const K1 = Kbase - first.total;
        if (K1 <= 0) continue;

        for (const meaty of meatyCandidates) {
          for (let d = 0; d <= maxDelay; d++) {
            tryMeaty(
              kdMove,
              kdInfo,
              [first],
              K1 + d,
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
            const K2 = K1 - second.total;
            if (K2 <= 0) continue;

            for (const meaty of meatyCandidates) {
              for (let d = 0; d <= maxDelay; d++) {
                tryMeaty(
                  kdMove,
                  kdInfo,
                  [first, second],
                  K2 + d,
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
                const K3 = K2 - third.total;
                if (K3 <= 0) continue;

                for (const meaty of meatyCandidates) {
                  for (let d = 0; d <= maxDelay; d++) {
                    tryMeaty(
                      kdMove,
                      kdInfo,
                      [first, second, third],
                      K3 + d,
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
