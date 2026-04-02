export function createMeatyState() {
  return {
    lastResults: null,
    charList: [],
    charFileMap: new Map(),
    charDataCache: new Map(),
    currentCharData: null,
  };
}

function getCharDataUrl(state, charName) {
  const file = state.charFileMap.get(charName) || `${charName}.json`;
  const encodedPath = String(file)
    .split("/")
    .map((seg) => encodeURIComponent(seg))
    .join("/");
  return `data/${encodedPath}`;
}

export async function ensureCharData(state, charName) {
  if (!charName) return null;
  if (state.charDataCache.has(charName))
    return state.charDataCache.get(charName);

  const resp = await fetch(getCharDataUrl(state, charName));
  if (!resp.ok) throw new Error(`${charName}: HTTP ${resp.status}`);

  const data = await resp.json();
  state.charDataCache.set(charName, data);
  return data;
}

export async function loadCharIndex() {
  const resp = await fetch("data/characters.index.json");
  if (!resp.ok) throw new Error(`characters.index.json HTTP ${resp.status}`);

  const payload = await resp.json();
  if (Array.isArray(payload)) {
    return payload.map((name) => ({
      name: String(name),
      file: `${name}.json`,
    }));
  }

  return (payload.characters || [])
    .map((x) => ({
      name: String(x.name || ""),
      file: String(x.file || ""),
    }))
    .filter((x) => x.name);
}

export async function loadData(state, onLoadedUi) {
  const indexItems = await loadCharIndex();
  state.charList = indexItems.map((x) => x.name);
  state.charFileMap.clear();

  for (const x of indexItems) {
    state.charFileMap.set(x.name, x.file || `${x.name}.json`);
  }

  if (!state.charList.length) throw new Error("No characters in index");

  await onLoadedUi();
}
