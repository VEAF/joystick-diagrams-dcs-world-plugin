"""Effective bindings: module defaults + diffs, computed by the Lua loader.

Runs against a minimal fake DCS install (tests/data/dcs_world/effective_install). Needs a Lua 5.1
interpreter: DCS_TEST_LUA if set (the CI sets it, so a missing interpreter fails there), else
lua5.1 or a lua that is 5.1 on the PATH; the tests are skipped when none is found.
"""

import logging
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import dcs_world_plugin.effective_bindings as effective
from dcs_world_plugin.dcs_world import DCSWorldParser
from joystick_diagrams.input.button import Button
from joystick_diagrams.input.device import Device_

ROOT = Path("tests/data/dcs_world/effective_install")
INSTALL = ROOT / "DCS World"
SAVED_GAMES = ROOT / "Saved Games" / "DCS"
STICK = "Fake Stick {84180FE0-BDD3-11ea-8001-444553540000}"
THROTTLE = "Fake Throttle {84180FE0-BDD3-11ea-8002-444553540000}"


def find_lua51() -> str | None:
    if os.environ.get("DCS_TEST_LUA"):
        return os.environ["DCS_TEST_LUA"]
    for name in ("lua5.1", "lua"):
        path = shutil.which(name)
        if path:
            version = subprocess.run(
                [path, "-v"], capture_output=True, text=True, check=False
            )
            if "Lua 5.1" in version.stdout + version.stderr:
                return path
    return None


@pytest.fixture(scope="module")
def lua():
    interpreter = find_lua51()
    if not interpreter:
        pytest.skip("no Lua 5.1 interpreter (set DCS_TEST_LUA)")
    return interpreter


@pytest.fixture(scope="module")
def result(lua):
    return effective.load_effective_bindings(
        INSTALL,
        SAVED_GAMES,
        ["FakePlane", "SecondPlane_pilot", "MissingPlane", "CommunityPlane", "UiLayer"],
        lua_interpreter=lua,
    )


def bindings(result, profile, device):
    devices = {d["name"]: d for d in result["profiles"][profile]["devices"]}
    return {
        (b["key"], tuple(b["reformers"]), b["command"])
        for b in devices[device]["bindings"]
    }


def test_module_defaults_are_included(result):
    stick = bindings(result, "FakePlane", STICK)
    assert ("JOY_BTN1", (), "Weapon Release") in stick
    assert ("JOY_BTN_POV1_U", (), "Sensor Up") in stick
    assert ("JOY_X", (), "Roll") in stick  # from DefaultAssignments


def test_removed_default_is_gone(result):
    stick = bindings(result, "FakePlane", STICK)
    assert not [b for b in stick if b[0] == "JOY_BTN2"]
    assert not [b for b in stick if b[0] == "JOY_Z"]


def test_added_binding_with_modifier(result):
    stick = bindings(result, "FakePlane", STICK)
    assert ("JOY_BTN6", (), "Gun Trigger") in stick
    assert ("JOY_BTN4", ("JOY_BTN5",), "Master Arm") in stick


def test_changed_axis_is_kept(result):
    assert ("JOY_Y", (), "Zoom") in bindings(result, "FakePlane", STICK)


def test_current_command_name_replaces_the_name_stored_in_the_diff(result):
    stick = bindings(result, "FakePlane", STICK)
    assert ("JOY_BTN7", (), "Trim: Nose Up") in stick
    assert not [b for b in stick if b[2] == "Trim Up"]


def test_default_bound_elsewhere_by_the_diff_is_kept_as_dcs_does(result):
    # Data.lua keeps a default combo another command's diff also uses (a conflict in the UI)
    assert ("JOY_BTN6", (), "Sensor Select") in bindings(result, "FakePlane", STICK)


def test_device_template_is_the_base(result):
    throttle = bindings(result, "FakePlane", THROTTLE)
    assert ("JOY_BTN10", (), "Speed Brake") in throttle
    assert ("JOY_BTN10", ("JOY_BTN5",), "Speed Brake") in throttle
    assert ("JOY_RX", (), "Roll") in throttle  # device-specific DefaultAssignments
    # the template diff only serves when the user has no diff for the device
    assert not [b for b in throttle if b[0] == "JOY_BTN11"]


def test_injected_commands_are_included(result):
    stick = bindings(result, "FakePlane", STICK)
    assert ("JOY_BTN20", (), "Laser Arm (community)") in stick


def test_commands_sharing_a_hash_give_one_binding(result):
    stick = bindings(result, "FakePlane", STICK)
    assert [b for b in stick if b[0] == "JOY_BTN1"] == [
        ("JOY_BTN1", (), "Weapon Release")
    ]


def test_engine_command_number_is_learned_by_majority(result):
    assert result["symbol_conflicts"] == {"iCommandPlaneTrimUp": {"100": 2, "101": 1}}
    devices = {d["name"]: d for d in result["profiles"]["FakePlane"]["devices"]}
    hashes = {b["command"]: b["hash"] for b in devices[STICK]["bindings"]}
    assert hashes["Trim: Nose Up"] == "dnilp100unilcdnilvdnilvpnilvunil"


def test_unit_name_comes_from_entry_lua(result):
    profile = result["profiles"]["SecondPlane_pilot"]
    assert profile["found"]
    assert profile["profile_folder"].endswith("SecondPlane/Input/Second/")


def test_unit_without_joystick_profile_uses_the_default_unit(result):
    stick = bindings(result, "SecondPlane_pilot", STICK)
    assert stick == {("JOY_BTN12", (), "Pause"), ("JOY_BTN13", (), "Pause")}


def test_module_not_installed_is_not_found(result):
    assert result["profiles"]["MissingPlane"] == {"found": False, "devices": []}


def test_community_module_in_saved_games_is_found(result):
    assert ("JOY_BTN1", (), "Tailhook") in bindings(result, "CommunityPlane", STICK)
    assert ("JOY_BTN2", (), "Tailhook") in bindings(result, "CommunityPlane", STICK)


def test_device_without_base_profile_is_reported(result):
    devices = result["profiles"]["UiLayer"]["devices"]
    assert devices == [{"name": STICK, "error": "no base profile"}]


def test_non_ascii_paths(lua, tmp_path):
    # luae.exe opens files in UTF-8; a stock Lua 5.1 on Windows uses the ANSI code page
    if os.name == "nt" and "luae" not in Path(lua).name.lower():
        pytest.skip("a stock Lua 5.1 on Windows cannot open UTF-8 paths")
    root = tmp_path / "Jérôme"
    shutil.copytree(ROOT, root)
    stick = STICK.replace("Fake Stick", "Contrôleur")
    folder = (
        root / "Saved Games" / "DCS" / "Config" / "Input" / "FakePlane" / "joystick"
    )
    (folder / f"{STICK}.diff.lua").rename(folder / f"{stick}.diff.lua")
    result = effective.load_effective_bindings(
        root / "DCS World", root / "Saved Games" / "DCS", ["FakePlane"], lua
    )
    assert ("JOY_BTN7", (), "Trim: Nose Up") in bindings(result, "FakePlane", stick)


def test_interpreter_failure_raises():
    with pytest.raises(effective.EffectiveBindingsError, match="exited with code"):
        # not Lua: python rejects the "-e" option and exits with an error
        effective.load_effective_bindings(
            INSTALL, SAVED_GAMES, ["FakePlane"], lua_interpreter=sys.executable
        )


def test_invalid_output_raises(monkeypatch):
    monkeypatch.setattr(
        effective.subprocess,
        "run",
        lambda *a, **k: subprocess.CompletedProcess(a, 0, b"not json", b""),
    )
    with pytest.raises(effective.EffectiveBindingsError, match="invalid output"):
        effective.load_effective_bindings(INSTALL, SAVED_GAMES, ["FakePlane"])


def test_missing_interpreter_raises():
    with pytest.raises(effective.EffectiveBindingsError):
        effective.load_effective_bindings(
            INSTALL, SAVED_GAMES, ["FakePlane"], lua_interpreter=INSTALL / "nope.exe"
        )


def test_registry_detection_is_windows_only(monkeypatch):
    monkeypatch.setattr(effective.sys, "platform", "linux")
    assert effective.detect_dcs_install_dir() is None


# Parser: Profile_ / Device_ built from the effective bindings


def parse(lua, install_dir, profiles):
    parser = DCSWorldParser(SAVED_GAMES, install_dir=install_dir, lua_interpreter=lua)
    return parser.process_profiles(profiles)


def device_of(collection, profile, device):
    guid = Device_.validate_guid(device.split("{")[1].rstrip("}"))
    return collection.get_profile(profile).get_device(guid)


def test_parser_builds_devices_from_effective_bindings(lua):
    collection = parse(lua, INSTALL, ["FakePlane"])
    stick = device_of(collection, "FakePlane", STICK)
    assert stick.name == "Fake Stick"
    inputs = stick.get_combined_inputs()
    assert inputs["BUTTON_1"].command == "Weapon Release"
    assert inputs["BUTTON_7"].command == "Trim: Nose Up"
    assert inputs["POV_1_U"].command == "Sensor Up"
    assert inputs["AXIS_X"].command == "Roll"
    assert "BUTTON_2" not in inputs
    master_arm = inputs["BUTTON_4"]
    assert master_arm.command == ""
    assert [(m.modifiers, m.command) for m in master_arm.modifiers] == [
        ({"JOY_BTN5"}, "Master Arm")
    ]


def test_parser_shows_every_command_of_a_shared_input(lua):
    collection = parse(lua, INSTALL, ["FakePlane"])
    inputs = device_of(collection, "FakePlane", STICK).get_combined_inputs()
    assert inputs["BUTTON_6"].command == "Gun Trigger / Sensor Select"


def test_parser_shows_a_released_switch_on_its_button(lua):
    collection = parse(lua, INSTALL, ["FakePlane"])
    inputs = device_of(collection, "FakePlane", STICK).get_combined_inputs()
    assert inputs["BUTTON_8"].command == "Gear Up / Gear Down (OFF)"


def test_released_switch_in_diff_only_parsing():
    parser = DCSWorldParser(SAVED_GAMES)
    assert parser.convert_button_format("JOY_BTN17_OFF") == Button(17)
    collection = parser.process_profiles(["MissingPlane"])
    inputs = device_of(collection, "MissingPlane", STICK).get_combined_inputs()
    # both positions of the switch, whatever their order in the diff
    assert sorted(inputs["BUTTON_9"].command.split(" / ")) == [
        "Switch Pressed",
        "Switch Released (OFF)",
    ]


def test_parser_ignores_keyboard_keys_in_joystick_profiles(lua):
    collection = parse(lua, INSTALL, ["CommunityPlane"])
    inputs = device_of(collection, "CommunityPlane", STICK).get_combined_inputs()
    assert set(inputs) == {"BUTTON_1", "BUTTON_2"}


def test_parser_falls_back_to_diffs_for_a_device_without_base(lua, caplog):
    with caplog.at_level(logging.WARNING):
        collection = parse(lua, INSTALL, ["UiLayer"])
    inputs = device_of(collection, "UiLayer", STICK).get_combined_inputs()
    assert inputs["BUTTON_30"].command == "UI Layer Command"
    assert "no base profile, only its .diff.lua changes are shown" in caplog.text


def test_parser_falls_back_to_diffs_for_a_module_not_installed(lua, caplog):
    with caplog.at_level(logging.WARNING):
        collection = parse(lua, INSTALL, ["MissingPlane"])
    stick = device_of(collection, "MissingPlane", STICK)
    assert stick.get_combined_inputs()["BUTTON_1"].command == "Module Not Installed"
    assert "MissingPlane is not in the DCS install" in caplog.text


def test_parser_without_install_keeps_diff_only_parsing(caplog):
    with caplog.at_level(logging.WARNING):
        collection = parse(None, None, ["FakePlane"])
    inputs = device_of(collection, "FakePlane", STICK).get_combined_inputs()
    assert inputs["BUTTON_7"].command == "Trim Up"  # name stored in the diff
    assert "BUTTON_1" not in inputs  # module default, unknown without the install
    assert "no DCS install directory set" in caplog.text


def test_parser_falls_back_when_the_loader_fails(caplog):
    with caplog.at_level(logging.WARNING):
        collection = parse(INSTALL / "nope.exe", INSTALL, ["FakePlane"])
    inputs = device_of(collection, "FakePlane", STICK).get_combined_inputs()
    assert inputs["BUTTON_7"].command == "Trim Up"
    assert "effective bindings unavailable" in caplog.text
