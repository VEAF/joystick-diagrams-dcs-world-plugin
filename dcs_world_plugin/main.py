from pathlib import Path

from pydantic import Field

from joystick_diagrams.input.profile_collection import ProfileCollection
from joystick_diagrams.plugins.plugin_interface import PluginInterface
from joystick_diagrams.plugins.plugin_settings import PluginMeta, PluginSettings

from .dcs_world import DCSWorldParser
from .effective_bindings import detect_dcs_install_dir


class DCSSettings(PluginSettings):
    game_dir: Path | None = Field(
        default=None,
        title="DCS Saved Games Directory",
        json_schema_extra={
            "is_folder": True,
            "default_path": "~/Saved Games",
        },
    )
    dcs_install_dir: Path | None = Field(
        default_factory=detect_dcs_install_dir,
        title="DCS Install Directory",
        description="Folder of the DCS World game (the one holding bin/luae.exe), detected from the registry. Needed to show the module default bindings, not only your changes; leave empty to show your changes only.",
        json_schema_extra={
            "is_folder": True,
            "required": False,
            "default_path": "C:/Program Files/Eagle Dynamics",
        },
    )
    remove_easy_modes: bool = Field(
        default=True,
        title="Remove Easy Mode Profiles",
        description="Hides aircraft variants whose profile name ends with '_easy' (e.g. A-10A_easy). Requires re-running plugins to take effect.",
    )


class ParserPlugin(PluginInterface):
    plugin_meta = PluginMeta(
        id="ea2a7f6a-cbf3-4f81-91ed-fdc81dd13af8",
        name="DCS World",
        version="2.0.0",
        icon_path="img/dcs.ico",
    )
    plugin_settings_model = DCSSettings

    def __init__(self):
        super().__init__()
        self.instance: DCSWorldParser | None = None

    def process(self) -> ProfileCollection:
        if self.instance:
            return self.instance.process_profiles()
        return ProfileCollection()

    def _rebuild_instance(self) -> None:
        game_dir = self.get_setting("game_dir")
        if game_dir and Path(game_dir).exists():
            try:
                self.instance = DCSWorldParser(
                    game_dir,
                    easy_modes=self.get_setting("remove_easy_modes"),
                    install_dir=self.get_setting("dcs_install_dir"),
                )
            except (FileNotFoundError, FileExistsError):
                self.instance = None
                raise
        else:
            self.instance = None

    def update_setting(self, key: str, value) -> None:
        super().update_setting(key, value)
        self._rebuild_instance()

    def on_settings_loaded(self) -> None:
        self._rebuild_instance()


if __name__ == "__main__":
    plugin = ParserPlugin()
