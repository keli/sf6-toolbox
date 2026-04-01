import { t } from "./i18n.js";

function calculateEloWinProbability(ratingA, ratingB) {
    return 1 / (1 + Math.pow(10, (ratingB - ratingA) / 400));
}

function binomialCoefficient(n, k) {
    if (k < 0 || k > n) return 0;
    if (k === 0 || k === n) return 1;
    let result = 1;
    for (let i = 1; i <= k; i++) {
        result *= (n - i + 1) / i;
    }
    return result;
}

function calculateBestOfWinProbability(gameWinProb, bestOf) {
    const winsNeeded = Math.ceil(bestOf / 2);
    let totalProb = 0;
    for (let losses = 0; losses < winsNeeded; losses++) {
        const wins = winsNeeded;
        const totalGames = wins + losses;
        const combinations = binomialCoefficient(totalGames - 1, wins - 1);
        const probability =
            combinations * Math.pow(gameWinProb, wins) * Math.pow(1 - gameWinProb, losses);
        totalProb += probability;
    }
    return totalProb;
}

export function eloCalculate() {
    const ratingA = parseFloat(document.getElementById("ratingA").value);
    const ratingB = parseFloat(document.getElementById("ratingB").value);
    const matchType = parseInt(document.getElementById("matchType").value);

    const gameWinProbA = calculateEloWinProbability(ratingA, ratingB);
    const gameWinProbB = 1 - gameWinProbA;

    const setWinProbA = calculateBestOfWinProbability(gameWinProbA, 3);
    const setWinProbB = 1 - setWinProbA;

    const matchWinProbA = calculateBestOfWinProbability(setWinProbA, matchType);
    const matchWinProbB = 1 - matchWinProbA;

    document.getElementById("matchHeader").textContent = t("elo_match_winrate", matchType);

    document.getElementById("singleWinRateA").textContent = (gameWinProbA * 100).toFixed(2) + "%";
    document.getElementById("singleWinRateB").textContent = (gameWinProbB * 100).toFixed(2) + "%";
    document.getElementById("setWinRateA").textContent = (setWinProbA * 100).toFixed(2) + "%";
    document.getElementById("setWinRateB").textContent = (setWinProbB * 100).toFixed(2) + "%";
    document.getElementById("matchWinRateA").textContent = (matchWinProbA * 100).toFixed(2) + "%";
    document.getElementById("matchWinRateB").textContent = (matchWinProbB * 100).toFixed(2) + "%";

    document.getElementById("elo-results").classList.add("show");
}

export function refreshForLanguage() {
    if (document.getElementById("elo-results").classList.contains("show")) {
        eloCalculate();
    }
}

export function initElo() {
    document.getElementById("eloCalcBtn").addEventListener("click", eloCalculate);
    document.getElementById("ratingA").addEventListener("keypress", (e) => {
        if (e.key === "Enter") eloCalculate();
    });
    document.getElementById("ratingB").addEventListener("keypress", (e) => {
        if (e.key === "Enter") eloCalculate();
    });
}
