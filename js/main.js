import { initLang, setLang } from "./i18n.js";
import {
  initMeaty,
  refreshForLanguage as refreshMeatyForLanguage,
} from "./meaty/index.js";
import { initElo, refreshForLanguage as refreshEloForLanguage } from "./elo.js";
import { initTabs } from "./tabs.js";

async function main() {
  await initLang();

  initTabs();
  initElo();
  await initMeaty();

  document.querySelectorAll(".lang-btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      await setLang(btn.dataset.lang);
      refreshMeatyForLanguage();
      refreshEloForLanguage();
    });
  });
}

main();
