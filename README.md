# Joystick Diagrams — DCS World Plugin

Parser plugin for [Joystick Diagrams](https://github.com/Rexeh/joystick-diagrams) that reads
DCS World keybind exports and turns them into device profiles the app can draw.

This plugin is **not bundled** with the application. Install it from inside Joystick Diagrams via
**Plugins → Store**, or point the installer at a release ZIP below.

- **Plugin ID:** `ea2a7f6a-cbf3-4f81-91ed-fdc81dd13af8`
- **Type:** parser
- **Current version:** 2.0.0

## Repository layout

```
dcs_world_plugin/     # the importable plugin package — this folder is what ships in the release ZIP
  __init__.py
  main.py             # ParserPlugin entry point + DCSSettings
  dcs_world.py        # DCSWorldParser core logic
  dcs_world_yacc.py   # PLY grammar
  effective_bindings.py  # runs lua/effective_bindings.lua with DCS's own Lua interpreter
  lua/effective_bindings.lua  # module defaults + user diffs, as DCS computes them
  lextab.py           # generated PLY lexer table
  img/dcs.ico
tests/                # standalone tests + DCS fixtures
scripts/sign_plugin.py
```

## Effective bindings

A `.diff.lua` file in `Saved Games/DCS/Config/Input/<profile>/joystick/` only holds the user's changes against the module's defaults.
When the **DCS Install Directory** setting is set (it is detected from `HKCU\Software\Eagle Dynamics\DCS World*\Path`), the plugin shows the bindings DCS actually uses:

- the module's default bindings (`<module>/Input/<profile>/joystick/default.lua`, or the device template such as `Throttle - HOTAS Warthog.lua`; modules of the install and of `Saved Games/DCS/Mods/aircraft`), with the user's diff applied: removed defaults disappear, changed and added bindings appear;
- the current command names, not the ones stored in the diff when it was written;
- commands added by the [Quaggles Input Command Injector](https://github.com/Quaggles/dcs-input-command-injector), when its hook is installed;
- every command bound to an input, joined with ` / ` (DCS allows several).

`lua/effective_bindings.lua` reproduces `DCS World/Scripts/Input/Data.lua`. The default profiles are Lua programs, so the plugin runs it with `DCS World/bin/luae.exe`, the standalone Lua 5.1 interpreter DCS ships: no extra dependency, and command hashes are computed exactly as in the game.
The script and its input (paths, directory listings) go through stdin in UTF-8, because `luae.exe` cannot take a non-ASCII path on its command line.
Engine command numbers (`iCommand*`) live in the DCS executable; the script learns them from every diff of the install and of Saved Games (by command name), and the value most diffs agree on wins.

Without an install directory (leave the setting empty to get the old behaviour), for a profile whose module is not installed, or for a device DCS has no default profile for, the plugin falls back to reading the `added` entries of the diffs, and logs a warning.

## How it loads in the host

At runtime the host app imports this package and resolves `joystick_diagrams.*` against itself, so
imports of `joystick_diagrams.input.*`, `...plugin_interface`, and `...plugin_settings` stay
**absolute**. Intra-plugin imports (e.g. `from .dcs_world import DCSWorldParser`) are **relative**.

Installed plugins cannot ship their own PyPI dependencies — they run inside the host's frozen
environment. This plugin needs **`ply`**, which the host bundles for it.

## Development

```bash
# Install the host package (provides the joystick_diagrams SDK) plus dev tooling
pip install "joystick-diagrams @ git+https://github.com/Rexeh/joystick-diagrams@master"
pip install -e ".[dev]"

pytest tests/
ruff check .
```

The effective-bindings tests need a Lua 5.1 interpreter: `DCS_TEST_LUA` (e.g. `"C:/Program Files/Eagle Dynamics/DCS World/bin/luae.exe"` or `lua5.1`), else `lua5.1` / `lua` 5.1 on the `PATH`; they are skipped when none is found.

## Releasing

Tag a release as `vX.Y.Z` (matching `plugin_meta.version` in `main.py`). The release workflow
zips the `dcs_world_plugin/` folder, optionally signs it (see below), computes its SHA-256, and
publishes `dcs_world_plugin.zip` as a release asset.

Then update the catalog manifest entry (`download_url` + `sha256`) that the app reads.

### Signing (for first-party "verified" releases)

The store shows this plugin as **Verified** only if the release ZIP contains a valid `plugin.sig`.
Signing uses the project's Ed25519 developer **private** key, stored as the repository/organisation
Actions secret `PLUGIN_SIGNING_KEY` (PEM). The matching public key is baked into the host
(`joystick_diagrams/plugins/plugin_signing.py`). Without the secret the workflow still ships an
**unsigned** ZIP (installs with a trust prompt).
