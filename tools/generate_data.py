#!/usr/bin/env python3
"""Generates SilkRoad's static game data for one game version from Blizzard's
client tables (DB2), as exported by wago.tools.

    python tools/generate_data.py                      # Forever, default build
    python tools/generate_data.py --build 1.60.1.70938 --flavor forever

Output: SilkRoad/Data/<Flavor>/Recipes.lua, loaded only on that client.

What comes from where:
  SkillLine          professions (names, icons)
  SkillLineAbility   recipe spells per profession, skill-up colours, auto-learned flag
  SpellName          recipe names
  SpellEffect        product item and quantity (effect 24 = create item)
  SpellReagents      reagents and counts
  ItemXItemEffect +  recipe items (patterns, plans, ...): item effects with
  ItemEffect         trigger type 6 teach the recipe spell
  ItemSparse + Item  item names, quality, icon, vendor buy/sell prices,
                     recipe items' required skill

Where recipes are obtained (vendors, drops, quests) is server-side data and
isn't in the client tables; SilkRoad reads it at runtime from QuestieDB.

Downloaded tables are cached in tools/.cache/<build>/ (git-ignored).
"""
import argparse
import csv
import pathlib
import urllib.request
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent

FLAVORS = {
    # flavor: (default build, data folder, recipe spell IDs to drop)
    # Forever's client tables still contain Season of Discovery recipes (spell
    # IDs 100000-999999); Forever re-created the ones it kept under new IDs.
    "forever": ("1.60.1.70938", "Forever", range(100000, 1000000)),
}

# Primary professions are SkillLine category 11, secondary ones 9. Rogue
# poisons (category 9) are a class skill, not a profession.
PROFESSION_CATEGORIES = {"11": "primary", "9": "secondary"}
EXCLUDED_SKILL_LINES = {40}  # Poisons

CREATE_ITEM, ENCHANT_ITEM = "24", "53"
TEACHES_SPELL_TRIGGER = "6"
ACQUIRE_ON_LEARN = "1"  # learned together with the profession

MIN_RECIPES_PER_PROFESSION = 2


def is_placeholder(name):
    lowered = name.lower()
    return "[dnt]" in lowered or "[ph]" in lowered or lowered.startswith("test ")


TABLES = ["SkillLine", "SkillLineAbility", "SpellName", "SpellEffect", "SpellReagents",
          "ItemXItemEffect", "ItemEffect", "ItemSparse", "Item"]


def fetch(build, table, cache):
    path = cache / f"{table}.csv"
    if not path.exists():
        url = f"https://wago.tools/db2/{table}/csv?build={build}"
        print("downloading", url)
        cache.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(url) as response:
            path.write_bytes(response.read())
    with path.open(encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def num(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0
    return int(number) if number == int(number) else number


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def build_data(build, cache, excluded_spells):
    t = {name: fetch(build, name, cache) for name in TABLES}

    spell_names = {int(r["ID"]): r["Name_lang"] for r in t["SpellName"]}
    item_sparse = {int(r["ID"]): r for r in t["ItemSparse"]}
    item_icons = {int(r["ID"]): num(r["IconFileDataID"]) for r in t["Item"]}

    effects = defaultdict(list)
    for r in t["SpellEffect"]:
        effects[int(r["SpellID"])].append(r)
    reagents = {int(r["SpellID"]): r for r in t["SpellReagents"]}

    item_effects = {int(r["ID"]): r for r in t["ItemEffect"]}
    recipe_items = defaultdict(list)  # spell -> items that teach it
    for r in t["ItemXItemEffect"]:
        effect = item_effects.get(int(r["ItemEffectID"]))
        item_id = int(r["ItemID"])
        if effect and effect["TriggerType"] == TEACHES_SPELL_TRIGGER and item_id in item_sparse:
            recipe_items[int(effect["SpellID"])].append(item_id)

    professions = {}
    for r in t["SkillLine"]:
        skill_id = int(r["ID"])
        if r["CategoryID"] in PROFESSION_CATEGORIES and skill_id not in EXCLUDED_SKILL_LINES:
            professions[skill_id] = {
                "name": r["DisplayName_lang"],
                "icon": num(r["SpellIconFileID"]),
                "kind": PROFESSION_CATEGORIES[r["CategoryID"]],
            }

    recipes, used_items = {}, set()
    for ability in t["SkillLineAbility"]:
        skill_id, spell = int(ability["SkillLine"]), int(ability["Spell"])
        if skill_id not in professions or spell in excluded_spells or spell not in reagents:
            continue
        spell_effects = effects.get(spell, [])
        create = next((e for e in spell_effects if e["Effect"] == CREATE_ITEM), None)
        enchant = any(e["Effect"] == ENCHANT_ITEM for e in spell_effects)
        product = int(create["EffectItemType"]) if create else None
        if product is not None and product not in item_sparse:
            continue  # makes an item this client doesn't have (removed content)
        if product is None and not enchant:
            continue
        if is_placeholder(spell_names.get(spell, "")):
            continue

        row = reagents[spell]
        reagent_list = []
        for i in range(8):
            item_id, count = int(row[f"Reagent_{i}"]), int(row[f"ReagentCount_{i}"])
            if item_id > 0 and count > 0:
                if item_id not in item_sparse:
                    break
                reagent_list += [item_id, count]
        else:
            if not reagent_list:
                continue
            taught_by = sorted(recipe_items.get(spell, []))
            recipe_item = taught_by[0] if taught_by else None
            yellow, gray = int(ability["TrivialSkillLineRankLow"]), int(ability["TrivialSkillLineRankHigh"])
            if recipe_item and int(item_sparse[recipe_item]["RequiredSkillRank"]) > 0:
                learn, exact = int(item_sparse[recipe_item]["RequiredSkillRank"]), True
            elif ability["AcquireMethod"] == ACQUIRE_ON_LEARN:
                learn, exact = 1, True
            else:
                learn, exact = max(1, yellow), False  # trainer: the yellow threshold is the closest value
            quantity = max(1, num(create["EffectBasePointsF"])) if create else 0
            recipes[spell] = {
                "skill": skill_id, "name": spell_names.get(spell, f"Recipe {spell}"),
                "product": product, "quantity": quantity, "learn": learn, "yellow": yellow,
                "gray": gray, "exact": exact, "auto": ability["AcquireMethod"] == ACQUIRE_ON_LEARN,
                "recipeItem": recipe_item, "reagents": reagent_list,
            }
            used_items.update(i for i in (product, recipe_item) if i)
            used_items.update(reagent_list[0::2])

    items = {}
    for item_id in used_items:
        r = item_sparse[item_id]
        items[item_id] = (r["Display_lang"], num(r["OverallQualityID"]), item_icons.get(item_id, 0),
                          num(r["SellPrice"]), num(r["BuyPrice"]), max(1, num(r["VendorStackCount"])))

    counts = defaultdict(int)
    for recipe in recipes.values():
        counts[recipe["skill"]] += 1
    # Drop internal/test lines and skill lines with a single stray recipe.
    professions = {k: v for k, v in professions.items()
                   if counts[k] >= MIN_RECIPES_PER_PROFESSION and not is_placeholder(v["name"])}
    recipes = {k: v for k, v in recipes.items() if v["skill"] in professions}
    used = set()
    for r in recipes.values():
        used.update(i for i in (r["product"], r["recipeItem"]) if i)
        used.update(r["reagents"][0::2])
    items = {k: v for k, v in items.items() if k in used}
    return professions, recipes, items, counts


def write_lua(path, flavor, build, professions, recipes, items):
    out = []
    w = out.append
    w(f"-- SilkRoad static game data for {flavor.title()} (client build {build}).")
    w("-- GENERATED by tools/generate_data.py from Blizzard's client tables via wago.tools.")
    w("-- Do not edit by hand; regenerate instead.")
    w("local _, SR = ...")
    w(f'if SR.flavor ~= "{flavor}" then return end')
    w("")
    w("local data = {")
    w(f'\tbuild = "{build}",')
    w("")
    w("\t-- { id = skillLineID, name, icon, kind = primary|secondary }")
    w("\tprofessions = {")
    for skill_id, p in sorted(professions.items(), key=lambda kv: (kv[1]["kind"] != "primary", kv[1]["name"])):
        w(f'\t\t{{ id = {skill_id}, name = {lua_string(p["name"])}, icon = {p["icon"]}, kind = "{p["kind"]}" }},')
    w("\t},")
    w("")
    w("\t-- [recipeSpellID] = { skillLine, name, productItemID|false, quantity, learnSkill, yellowSkill,")
    w("\t--   graySkill, flags (1 = learnSkill exact, 2 = learned with the profession),")
    w("\t--   recipeItemID|false, { reagentItemID, count, reagentItemID, count, ... } }")
    w("\trecipes = {")
    for spell, r in sorted(recipes.items()):
        flags = (1 if r["exact"] else 0) | (2 if r["auto"] else 0)
        reagent_text = ", ".join(str(v) for v in r["reagents"])
        w(f'\t\t[{spell}] = {{ {r["skill"]}, {lua_string(r["name"])}, {r["product"] or "false"}, {r["quantity"]}, '
          f'{r["learn"]}, {r["yellow"]}, {r["gray"]}, {flags}, {r["recipeItem"] or "false"}, {{ {reagent_text} }} }},')
    w("\t},")
    w("")
    w("\t-- [itemID] = { name, quality, iconFileID, vendorSellPrice, vendorBuyPrice, vendorBuyStack }")
    w("\titems = {")
    for item_id, (name, quality, icon, sell, buy, stack) in sorted(items.items()):
        w(f"\t\t[{item_id}] = {{ {lua_string(name)}, {quality}, {icon}, {sell}, {buy}, {stack} }},")
    w("\t},")
    w("}")
    w("")
    w("SR.StaticData = data")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--flavor", default="forever", choices=sorted(FLAVORS))
    parser.add_argument("--build", help="client build, e.g. 1.60.1.70938 (default: the flavor's pinned build)")
    args = parser.parse_args()

    default_build, folder, excluded = FLAVORS[args.flavor]
    build = args.build or default_build
    cache = ROOT / "tools" / ".cache" / build
    professions, recipes, items, counts = build_data(build, cache, excluded)

    path = ROOT / "SilkRoad" / "Data" / folder / "Recipes.lua"
    write_lua(path, args.flavor, build, professions, recipes, items)
    print(f"wrote {path.relative_to(ROOT)}: {len(recipes)} recipes, {len(items)} items, "
          f"{path.stat().st_size // 1024} KB")
    for skill_id, p in sorted(professions.items(), key=lambda kv: kv[1]["name"]):
        print(f"  {p['name']:<16} {counts[skill_id]:>4} recipes")


if __name__ == "__main__":
    main()
