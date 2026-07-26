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
  lextab.py           # generated PLY lexer table
  img/dcs.ico
tests/                # standalone tests + DCS fixtures
scripts/sign_plugin.py
```

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
