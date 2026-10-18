# VEAF — joystick-diagrams-dcs-world-plugin

Fork VEAF du [plugin DCS World de Joystick Diagrams](https://github.com/Rexeh/joystick-diagrams-dcs-world-plugin) (remote `upstream`, mainteneur Rexeh, GPL v2).

Le chantier est suivi ici : PRD = issue [#1](https://github.com/VEAF/joystick-diagrams-dcs-world-plugin/issues/1), tickets en sous-issues.
Labels : `upstream` pour le travail destiné à une PR chez Rexeh, `veaf-only` pour ce qui reste dans le fork.

## PR vers l'upstream

Toute PR destinée à `Rexeh/joystick-diagrams-dcs-world-plugin` se base sur `upstream/main`, jamais sur la `main` du fork.

- `git fetch upstream`, puis créer la branche depuis `upstream/main`.
- Ouvrir la PR avec `--repo Rexeh/joystick-diagrams-dcs-world-plugin --base main`, rédigée en anglais.
- `CLAUDE.md` n'existe que dans notre fork et ne doit jamais arriver chez Rexeh. Avant d'ouvrir la PR, vérifier que `git diff --stat upstream/main...HEAD` ne liste pas `CLAUDE.md` (ni aucun autre fichier propre à VEAF).
- Ne pas toucher `scripts/sign_plugin.py` ni `.github/workflows/release.yml` : les zips sont signés par le mainteneur.
