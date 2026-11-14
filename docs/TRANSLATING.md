# Translating SilkRoad

SilkRoad shows its own text in the game client's language when a translation
exists, and falls back to English for anything untranslated.

## What needs translating (and what doesn't)

- **SilkRoad's own text** (buttons, headers, messages, help) lives in
  `SilkRoad/Locales/`. This is what translators work on.
- **Game names** (recipes, items, professions, zones, NPCs, quests) need no
  translating. SilkRoad asks the game for them in its own language. The
  generated data in `Data/<Version>/` is English and is only a fallback. Item
  names stay English until the client has seen the item (it caches them as you
  play).

## How the strings work

- `Locales/enUS.lua` is the base. Short texts use their English text as the
  key: `L["Recipes"]` shows "Recipes" unless a translation overrides it.
  Longer texts use symbolic keys defined there, like `L.RECIPES_DESC`.
- `Locales/<locale>.lua` holds one language. It starts with a check so it only
  takes effect on a client in that language (`GetLocale()`), then assigns
  translations:

  ```lua
  L["Recipes"] = "Recetas"
  L.RECIPES_DESC = "Todas las recetas de todas las profesiones: ..."
  ```

- Keep placeholders exactly as in English (`%s`, `%d`, `%.1f`, `%d%%`) and in the
  same order, and keep colour codes (`|cffffd100...|r`).

## Adding a language

```powershell
python tools/locales.py --template frFR
```

This writes `SilkRoad/Locales/frFR.lua` with every string commented out, the
English text next to each one. Uncomment and translate what you can, then list
the file in `SilkRoad.toc` after `Locales\enUS.lua`. Client locales: deDE,
esES/esMX (one file: `esES.lua`), frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW.

## Checking

```powershell
python tools/locales.py
```

This reports, per language, how much is translated, and flags:

- symbolic keys used in the code but not defined in `enUS.lua` (a typo);
- translations of strings the code no longer uses;
- translations whose placeholders don't match the English.

The smoke test (`scripts/test.ps1`) runs this check, and also loads SilkRoad as
a Spanish client to make sure translations and game names show up.

## Writing code

Every text a player can see goes through `L`. Use the English text as the key
for short labels; add a symbolic key to `enUS.lua` for sentences and paragraphs.
Never build sentences by joining translated fragments; use one string with
placeholders, because word order differs between languages.
