function parseInt1(val) {
    if (val == null) return null;
    if (typeof val === "number") return val;
    if (typeof val === "object") {
        if (typeof val.first === "number") return val.first;
        if (typeof val.min === "number") return val.min;
        if (Array.isArray(val.numbers) && val.numbers.length) return val.numbers[0];
        if (typeof val.text === "string") {
            const m = val.text.match(/-?\d+/);
            return m ? parseInt(m[0]) : null;
        }
        return null;
    }
    const m = String(val).match(/-?\d+/);
    return m ? parseInt(m[0]) : null;
}

function parseIntWorst(val) {
    if (val == null) return null;
    if (typeof val === "number") return val;
    if (typeof val === "object") {
        if (typeof val.min === "number") return val.min;
        if (Array.isArray(val.numbers) && val.numbers.length) return Math.min(...val.numbers);
        if (typeof val.text !== "string") return null;
        val = val.text;
    }
    const nums = [...String(val).matchAll(/-?\d+/g)].map((m) => parseInt(m[0]));
    return nums.length ? Math.min(...nums) : null;
}

function parseKDField(val, hitType) {
    if (!val) return [];
    if (typeof val === "object" && Array.isArray(val.kd) && val.kd.length) {
        return val.kd
            .filter(
                (k) =>
                    k &&
                    typeof k.type === "string" &&
                    (typeof k.advantageMin === "number" || typeof k.advantage === "number"),
            )
            .map((k) => {
                const min = typeof k.advantageMin === "number" ? k.advantageMin : k.advantage;
                const max = typeof k.advantageMax === "number" ? k.advantageMax : min;
                return {
                    hitType,
                    kdType: k.type,
                    advantage: min,
                    advantageMin: min,
                    advantageMax: max,
                };
            });
    }
    if (typeof val !== "string") return [];
    const results = [];
    for (const m of val.matchAll(
        /(H?KD)\s*\+(-?\d+)(?:(?:\s*[~〜-]\s*(-?\d+))|(?:\s*\(\s*\+?\s*(-?\d+)\s*\)))?/g,
    )) {
        const a = parseInt(m[2]);
        const b = m[3] != null ? parseInt(m[3]) : m[4] != null ? parseInt(m[4]) : a;
        results.push({
            hitType,
            kdType: m[1],
            advantage: Math.min(a, b),
            advantageMin: Math.min(a, b),
            advantageMax: Math.max(a, b),
        });
    }
    for (const m of val.matchAll(/(-?\d+)(?:\s*[~〜-]\s*(-?\d+))?\s*\(\s*(H?KD)\s*\)/g)) {
        const a = parseInt(m[1]);
        const b = m[2] != null ? parseInt(m[2]) : a;
        results.push({
            hitType,
            kdType: m[3],
            advantage: Math.min(a, b),
            advantageMin: Math.min(a, b),
            advantageMax: Math.max(a, b),
        });
    }
    return results;
}

function isTumblePrimary(normField) {
    if (!normField || typeof normField !== "object") return false;
    const tags = normField.tags || [];
    if (!tags.includes("tumble")) return false;
    const kd = normField.kd || [];
    if (!kd.length) return false;
    const minKD = Math.min(...kd.map((k) => k.advantageMin ?? k.advantage));
    return normField.first > minKD;
}

function buildMoveSignature(mv) {
    const kdSig = (mv.knockdowns || [])
        .map(
            (k) =>
                `${k.hitType}:${k.kdType}:${k.advantageMin ?? k.advantage}:${k.advantageMax ?? k.advantageMin ?? k.advantage}`,
        )
        .sort()
        .join(";");
    const cancelSig = (mv.cancelTypes || []).slice().sort().join(",");
    return [
        mv.cmd,
        mv.startup,
        mv.active,
        mv.total,
        mv.onBlock,
        mv.onHit,
        mv.isAttack,
        mv.isThrowLike,
        cancelSig,
        kdSig,
    ].join("|");
}

export function extractMoves(charData) {
    const moves = [];
    for (const [catName, catMoves] of Object.entries(charData.moves || {})) {
        if (typeof catMoves !== "object") continue;
        for (const [moveKey, mv] of Object.entries(catMoves)) {
            if (typeof mv !== "object") continue;
            const moveName = mv.moveName || mv.cmnName || "";
            if (catName === "drive" && mv.nonHittingMove) continue;
            if (moveName === "Drive Rush") continue;
            const norm = mv.normalized || {};
            const startup = parseInt1(norm.startup ?? mv.startup);
            const active = parseInt1(norm.active ?? mv.active);
            const recovery = parseInt1(norm.recovery ?? mv.recovery);
            if (startup == null || active == null || active <= 0) continue;
            let total = parseInt1(mv.total);
            if (total == null) total = startup + active + (recovery || 0) - 1;

            const knockdowns = [
                ...(isTumblePrimary(norm.onHit) ? [] : parseKDField(norm.onHit ?? mv.onHit, "normal")),
                ...(isTumblePrimary(norm.onPC) ? [] : parseKDField(norm.onPC ?? mv.onPC, "pc")),
                ...parseKDField(mv.onCC, "cc"),
            ];
            const cmd = mv.numCmd || mv.plnCmd || moveKey;
            const atkLevel = mv.atkLvl == null ? "" : String(mv.atkLvl);
            const isThrowLike =
                atkLevel.toUpperCase() === "T" || catName === "throw" || catName === "command-grab";
            moves.push({
                name: mv.moveName || moveKey,
                cmd,
                startup,
                active,
                recovery: recovery || 0,
                total,
                onBlock: parseIntWorst(norm.onBlock ?? mv.onBlock),
                onHit: parseInt1(norm.onHit ?? mv.onHit),
                moveType: catName,
                isAttack: mv.atkLvl != null,
                isThrowLike,
                cancelTypes: mv.xx || [],
                knockdowns,
            });
        }
    }

    const fDash = parseInt1(charData.stats?.fDash);
    if (fDash) {
        moves.push({
            name: "Dash",
            cmd: "66",
            startup: fDash,
            active: 0,
            recovery: 0,
            total: fDash,
            onBlock: null,
            onHit: null,
            moveType: "dash",
            isAttack: false,
            knockdowns: [],
        });
    }

    const uniq = new Map();
    for (const mv of moves) {
        const key = buildMoveSignature(mv);
        if (!uniq.has(key)) uniq.set(key, mv);
    }
    return [...uniq.values()];
}
