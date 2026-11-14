#!/usr/bin/env python3
"""Runs SilkRoad outside the game, against the mock client in wow_mock.lua.

    pip install lupa
    python tests/smoke_test.py --api <path to BlizzardInterfaceResources/Resources>

The addon is compiled with real Lua 5.1 (the game's Lua version), loaded in
TOC order, and driven through tests/scenario.lua.

--api (or the WOW_API_RESOURCES environment variable) points at the Resources
folder of https://github.com/Ketho/BlizzardInterfaceResources, branch
"forever". With it, every widget method, frame template and game global the
addon touches is checked against the real Forever client API. Without it the
mock is permissive and only the addon's own logic is exercised.
"""
import argparse
import os
import pathlib
import re
import sys

from lupa import lua51
from lupa.lua51 import LuaError

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON_NAME = "SilkRoad"
ADDON_DIR = ROOT / ADDON_NAME
TESTS_DIR = ROOT / "tests"

# Checked by hand in the Forever UI source (github.com/Gethe/wow-ui-source,
# branch "forever") but absent from the generated API lists.
VERIFIED_BY_SOURCE = {
    "Settings.RegisterCanvasLayoutCategory",
    "Settings.RegisterAddOnCategory",
    "Settings.OpenToCategory",
    "ScrollBoxConstants",
    "UISpecialFrames",
    "SlashCmdList",
    "SOUNDKIT",
    "time",
    "UiMapPoint.CreateFromCoordinates",  # Blizzard_ObjectAPI/Mainline/UiMapPoint.lua
    "Minimap",  # nested <Minimap name="Minimap"> in Blizzard_Minimap/Mainline/Minimap.xml
    # Client constants (not in the generated lists) read by the vendored LibAHTab.
    "WOW_PROJECT_ID",
    "WOW_PROJECT_MAINLINE",
    "WOW_PROJECT_CAMELOT",
}

GUARD = """
local M = MOCK
setmetatable(_G, {
    __index = function(_, key)
        if M.allowedNilGlobals[key] then return nil end
        if M.knownAPI and M.knownAPI[key] then
            error("game API used but not mocked: " .. tostring(key), 2)
        end
        error("unknown global read: " .. tostring(key), 2)
    end,
    __newindex = function(t, key, value)
        if not M.allowedNewGlobals[key] then
            error("unexpected global write: " .. tostring(key), 2)
        end
        rawset(t, key, value)
    end,
})
"""

RUN_CHUNK = """
return function(source, chunkName, ...)
    local chunk, err = loadstring(source, chunkName)
    if not chunk then error(err, 0) end
    return chunk(...)
end
"""


def read_toc():
    fields, files = {}, []
    for line in (ADDON_DIR / f"{ADDON_NAME}.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("## "):
            key, _, value = line[3:].partition(":")
            fields[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return fields, files


def quoted_strings(path):
    return set(re.findall(r'"([^"\n]+)"', path.read_text(encoding="utf-8")))


def load_api(resources):
    widget_methods = quoted_strings(resources / "WidgetAPI.lua")
    api = set()
    for name in ("GlobalAPI.lua", "FrameXML.lua", "Frames.lua", "Mixins.lua"):
        api |= quoted_strings(resources / name)
    strings_file = (resources / "GlobalStrings" / "enUS.lua").read_text(encoding="utf-8")
    api |= set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=", strings_file, re.M))
    templates = dict(re.findall(
        r'\["([^"]+)"\]\s*=\s*\{type\s*=\s*"([^"]+)"',
        (resources / "Templates.lua").read_text(encoding="utf-8"),
    ))
    return widget_methods, api, templates


def find_unverified_mocks(lua, api):
    """Names the mock defines that don't exist in the real client API."""
    lua_type = lua.eval("type")
    known = api | VERIFIED_BY_SOURCE
    g = lua.globals()
    problems = []
    for name in g.MOCK.defined.values():
        if name in known:
            continue
        value = g[name]
        if lua_type(value) == "table":
            members = [f"{name}.{key}" for key in value.keys() if lua_type(value[key]) == "function"]
            problems += [member for member in members if member not in known]
            if not members:
                problems.append(name)
        else:
            problems.append(name)
    return problems


def mock_method_names(lua):
    return [key for key in lua.globals().MOCK.Widget.keys() if not key.startswith("__")]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api", default=os.environ.get("WOW_API_RESOURCES"),
                        help="BlizzardInterfaceResources/Resources folder (forever branch)")
    args = parser.parse_args()

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((TESTS_DIR / "wow_mock.lua").read_text(encoding="utf-8"))
    mock = lua.globals().MOCK

    toc_fields, toc_files = read_toc()
    mock.tocFields = lua.table_from(toc_fields)

    if args.api:
        widget_methods, api, templates = load_api(pathlib.Path(args.api))
        fake_methods = [name for name in mock_method_names(lua) if name not in widget_methods]
        fake_globals = find_unverified_mocks(lua, api)
        if fake_methods or fake_globals:
            print("The mock defines names that don't exist in the Forever API:")
            for name in fake_methods + fake_globals:
                print("  -", name)
            return 1
        mock.widgetMethods = lua.table_from({name: True for name in widget_methods})
        mock.knownAPI = lua.table_from({name: True for name in api})
        mock.templates = lua.table_from(templates)
        print(f"API check on: {len(widget_methods)} widget names, {len(api)} globals, {len(templates)} templates")
    else:
        print("API check off (pass --api to validate names against the Forever client API)")

    lua.execute(GUARD)
    run_chunk = lua.execute(RUN_CHUNK)
    namespace = lua.table()

    try:
        for relative in toc_files:
            source = (ADDON_DIR / relative).read_text(encoding="utf-8")
            run_chunk(source, f"@{ADDON_NAME}/{relative}", ADDON_NAME, namespace)
        print(f"Loaded {len(toc_files)} addon files")

        scenario = (TESTS_DIR / "scenario.lua").read_text(encoding="utf-8")
        checks = run_chunk(scenario, "@tests/scenario.lua")
    except LuaError as error:
        print("FAILED:", error)
        print("Last output:")
        for line in list(mock.output.values())[-15:]:
            print("  ", line)
        return 1

    print(f"PASSED: {checks} checks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
