# SheepHiResort

## Checks

Every pull request runs **Godot checks** on GitHub (`.github/workflows/godot-checks.yml`):

1. Every `res://` path in scripts, scenes and resources matches a real file with exactly the same capitals (exported builds are case-sensitive, Windows is not).
2. Godot imports the project and starts the game without errors.
3. The headless gameplay tests in `tests/` pass:

| Test | Checks |
|---|---|
| `test_week.gd` | A perfect player gets through the week; every forged paper can be proven by comparing two items |
| `test_grades.gd` | The S / A / B / D / F grade table |
| `test_endings.gd` | The 3rd wolf ends the game with an F, reputation 0 means fired, Play again resets the week |
| `test_paper_piles.gd` | The paper pile on the mat matches the day's papers |
| `test_sheep_characters.gd` | Every drawn sheep in `data/sheep_characters` has a body, a normal face, boxes on its sheet and a matching `_pixel` sprite |
| `test_sheep_generation.gd` | Guests get a real face of a playable sheep, red eyes only on wolves, forged ID photos are flaws from day 6 |

### Running them locally

From Git Bash in the project folder, with `GODOT` pointing at your Godot console executable:

```bash
export GODOT="/c/path/to/Godot_v4.7.2-stable_win64_console.exe"
bash tools/ci/check_res_paths.sh
bash tools/ci/godot_run.sh --import
bash tools/ci/godot_run.sh --fixed-fps 60 -s res://tests/test_week.gd
```

`--fixed-fps 60` makes the game run as fast as possible with steady timing, so a full week takes seconds.
