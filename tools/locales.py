#!/usr/bin/env python3
"""Checks and scaffolds SilkRoad's translations.

    python tools/locales.py                 # report: undefined, missing and unused strings
    python tools/locales.py --template frFR # write SilkRoad/Locales/frFR.lua to fill in

How SilkRoad's strings work (see SilkRoad/Locales/enUS.lua):
  * Short texts use their English text as the key: L["Recipes"]. Without a
    translation, the English key itself is shown.
  * Longer texts use symbolic keys: L.RECIPES_DESC, defined in enUS.lua.
  * Locales/<locale>.lua files only take effect on a client with that
    language (GetLocale()) and override what they translate.

Exit status 1 when the code uses a symbolic key that enUS.lua doesn't define,
or a locale file translates a key the code no longer uses.
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "SilkRoad"
LOCALES = ADDON / "Locales"

# Game client languages and the file that serves each.
CLIENT_LOCALES = {
    "deDE": "deDE", "esES": "esES", "esMX": "esES", "frFR": "frFR", "itIT": "itIT",
    "koKR": "koKR", "ptBR": "ptBR", "ruRU": "ruRU", "zhCN": "zhCN", "zhTW": "zhTW",
}

TEXT_KEY = re.compile(r'\bL\["((?:[^"\\]|\\.)*)"\]')
SYMBOL_KEY = re.compile(r"\bL\.([A-Z][A-Z0-9_]+)\b")
DEFINITION = re.compile(r'^L\.([A-Z][A-Z0-9_]+)\s*=|^L\["((?:[^"\\]|\\.)*)"\]\s*=', re.M)


def lua_files():
    return [p for p in ADDON.rglob("*.lua") if LOCALES not in p.parents and "Data" not in p.parts and "Libs" not in p.parts]


def used_keys():
    text, symbols = {}, {}
    for path in lua_files():
        source = path.read_text(encoding="utf-8")
        for match in TEXT_KEY.finditer(source):
            text.setdefault(match.group(1), path.relative_to(ADDON).as_posix())
        for match in SYMBOL_KEY.finditer(source):
            symbols.setdefault(match.group(1), path.relative_to(ADDON).as_posix())
    return text, symbols


def defined_keys(path):
    keys = set()
    for symbol, text in DEFINITION.findall(path.read_text(encoding="utf-8")):
        keys.add(symbol or text)
    return keys


def english_values():
    """Symbolic key -> English text, as written in enUS.lua (source form)."""
    source = (LOCALES / "enUS.lua").read_text(encoding="utf-8")
    values = {}
    for match in re.finditer(r'^L\.([A-Z][A-Z0-9_]+)\s*=\s*(.+?)\n(?=L\.|L\[|\Z|\n)', source, re.M | re.S):
        values[match.group(1)] = match.group(2).strip()
    return values


PLACEHOLDER = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdif%]")


def translations(path):
    """key -> translated source text (single-line values only)."""
    values = {}
    for match in re.finditer(r'^L(?:\.([A-Z][A-Z0-9_]+)|\["((?:[^"\\]|\\.)*)"\])\s*=\s*"((?:[^"\\]|\\.)*)"\s*$',
                             path.read_text(encoding="utf-8"), re.M):
        values[match.group(1) or match.group(2)] = match.group(3)
    return values


def placeholders(text):
    return sorted(PLACEHOLDER.findall(text))


def report():
    text, symbols = used_keys()
    english = defined_keys(LOCALES / "enUS.lua")
    problems = 0

    undefined = sorted(k for k in symbols if k not in english)
    for key in undefined:
        print(f"UNDEFINED  L.{key} (used in {symbols[key]}) is not defined in Locales/enUS.lua")
    problems += len(undefined)

    all_keys = set(text) | set(symbols)
    print(f"{len(text)} text keys and {len(symbols)} symbolic keys in use")
    for path in sorted(LOCALES.glob("*.lua")):
        if path.name == "enUS.lua":
            continue
        translated = defined_keys(path)
        missing = sorted(all_keys - translated)
        unused = sorted(translated - all_keys)
        print(f"{path.stem}: {len(translated & all_keys)}/{len(all_keys)} translated, {len(missing)} missing")
        for key in unused:
            print(f"  UNUSED   {key!r} is translated but no longer used")
        problems += len(unused)
        english_text = translations(LOCALES / "enUS.lua")
        for key, value in translations(path).items():
            original = english_text.get(key, key)
            if placeholders(original) != placeholders(value):
                print(f"  FORMAT   {key!r}: placeholders {placeholders(value)} don't match the English {placeholders(original)}")
                problems += 1
    return 1 if problems else 0


def lua_quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def template(locale):
    served_by = CLIENT_LOCALES.get(locale)
    if not served_by:
        sys.exit(f"unknown client locale {locale}; one of {', '.join(sorted(CLIENT_LOCALES))}")
    path = LOCALES / f"{served_by}.lua"
    if path.exists():
        sys.exit(f"{path.relative_to(ROOT)} already exists")
    clients = [c for c, f in CLIENT_LOCALES.items() if f == served_by]
    condition = " or ".join(f'locale == "{c}"' for c in clients)
    text, symbols = used_keys()
    english = english_values()
    lines = [
        f"--[[ SilkRoad - Locales/{served_by}.lua",
        "\tTranslations for " + ", ".join(clients) + " clients. Untranslated strings fall back to English.",
        "\tFill in the values; keep %s, %d and |c...|r codes as they are.",
        "]]",
        "local _, SR = ...",
        "local locale = GetLocale()",
        f"if not ({condition}) then",
        "\treturn",
        "end",
        "local L = SR.L",
        "",
    ]
    for key in sorted(symbols):
        lines.append(f"-- L.{key} = {english.get(key, '?')}")
    lines.append("")
    for key in sorted(text):
        lines.append(f"-- L[{lua_quote(key)}] = {lua_quote(key)}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {path.relative_to(ROOT)}; add it to SilkRoad.toc after Locales\\enUS.lua")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--template", metavar="LOCALE", help="write a translation skeleton for a client locale")
    args = parser.parse_args()
    if args.template:
        template(args.template)
        return 0
    return report()


if __name__ == "__main__":
    sys.exit(main())
