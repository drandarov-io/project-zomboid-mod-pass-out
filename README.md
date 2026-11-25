# Pass out

Causes your character to fall asleep on the spot if you have max tiredness for X in-game hours (default 6). The amount of hours, whether a warning is given, and collapse behavior are configurable in the sandbox options.

This is intended for a more hardcore playthrough.

Dual-build compatible with **Build 42** (primary) and **Build 41** (backport).

---

### Thumbnail

<img src="workshop/poster.png" alt="Screenshot" width="800">

### Credits
- Original mod & concept by **DahakaMVl** (Dmitrij Drandarov)
- Build 42 port, traits, collapse animations & multiplayer fixes by **turnip**

---

### Features:

- **Build 42 & Build 41 Dual Support**:
  - `42/` subfolder structure with versioned `mod.info`, B42 APIs (`CharacterStat.PANIC`, `MoodleType.TIRED`), and `.json` translations.
  - Root `media/` backport preserving Build 41 legacy APIs and `.txt` translations.
- **Traits**:
  - **Prone to Passing Out** (+4 trait points / negative): More susceptible to passing out (20% less time before collapse, 50% faster blackout fade, panic save drains 20 points/min).
  - **Resistant to Passing Out** (-4 trait points / positive): Fights off unconsciousness longer (20% more time before collapse, 50% longer blackout fade, panic save drains only 5 points/min).
  - Mutually exclusive, full B42 registry scripts + B41 `TraitFactory` support, custom 18x18 trait icons included.
  - Build 42: only offered at character creation when the mod is enabled and the character can sleep (in multiplayer, the server needs `SleepAllowed` and `SleepNeeded` on).
- **Collapse Animation (Build 42)**:
  - Your character sinks to the ground (`sitonground`) when passing out instead of standing bolt upright with open eyes, and stands back up on waking (`forceGetUp`).
  - Mirrored onto remote sleepers in multiplayer.
- **Multiplayer & Split-Screen**:
  - Fully compatible with dedicated servers and split-screen couch co-op.
  - Movement lockout prevents the common MP instant-wake glitch where a held movement key would immediately cancel the collapse.
- **Vehicle Support**:
  - Slumping over the wheel honks the car horn and lets the car roll on until you stop or wake up.
  - Passing out at the wheel and the horn are separate sandbox toggles. The horn toggle is Build 42 only; Build 41 always honks.
- **Project Viewpoint Compatibility**:
  - Includes a UI-layer darkening vignette overlay when Viewpoint's first/third-person 3D mode is active.
- **Configurable Sandbox Options**:
  - Master on/off toggle.
  - Pass Out Hours & Randomness factor.
  - Required Tiredness Level (Exhausted, Very Tired, or Tired).
  - Passing Out Minutes (fade duration).
  - Warning toggle (private Halo text popup).
  - Panic Keeps You Awake toggle.
  - Forced Pass-Out Duration (locks early wake-by-moving in MP).
  - Pass-Out Sleep Quality (Floor, Rough, Average, Good).
  - Collapse Animation toggle.
  - Pass Out While Driving toggle.
  - Honk When Passing Out at the Wheel toggle (Build 42).

---

### Sandbox Options (Page: *Pass Out*)

| Option | Default | Description |
|--------|---------|-------------|
| Enable Pass Out | on | Master on/off switch for the mod. |
| Pass Out Hours | 6 | In-game hours at the required tiredness before passing out. |
| Pass Out Randomness | 0.2 | Randomly shifts the delay so timing isn't predictable. |
| Required Tiredness Level | 4 (Exhausted) | How tired before the countdown runs (4 = Exhausted, down to 2 = Tired). |
| Passing Out Minutes | 5 | How long the screen gradually blacks out before sleep. |
| Pass Out Warning | on | One-time on-screen warning ~10 in-game minutes before. |
| Panic Keeps You Awake | on | Panic delays the collapse and drains each minute until you drop. |
| Forced Pass-Out Duration (seconds) | 30 | MP and split-screen — real seconds you stay knocked out before moving wakes you. |
| Pass-Out Sleep Quality | Floor | How restful a collapse is (Floor → Good), using engine bed-quality recovery. |
| Collapse Animation | on | B42 only — sink to the ground when you drop instead of sleeping upright. |
| Pass Out While Driving | on | Drop at the wheel: the car keeps rolling. |
| Honk When Passing Out at the Wheel | on | B42 only: slump onto the horn when you drop at the wheel. Build 41 always honks. |

---

### Development

`42/` is the Build 42 version. The root `media/` and `workshop/mod.info` are the Build 41 version.

| Prerequisite | Needed for |
|--------------|------------|
| PowerShell 7 | All scripts |
| [project-zomboid-mod-toolkit](https://github.com/drandarov-io/project-zomboid-mod-toolkit) cloned next to this repository | All scripts |
| LuaJIT on `PATH`: `winget install DEVCOM.LuaJIT`, then a new terminal | Unit tests |
| The toolkit's workspace `.emmyrc.json` in the folder above both repositories and its `setup-umbrella.ps1` run once, see [Tooling](https://github.com/drandarov-io/project-zomboid-mod-toolkit/blob/master/MODDING.md#tooling) | Static check |

#### Running the tests

```powershell
.\test.ps1                    # static check of the Build 42 Lua, then the unit tests
.\test.ps1 -Filter pass_out   # only tests\pass_out*_spec.lua
```

The static check runs `emmylua_check` against the Umbrella stubs and the vanilla Lua and skips the Build 41 `media/`. The unit tests in [tests/pass_out_spec.lua](tests/pass_out_spec.lua) load the real Build 42 Lua under LuaJIT with the game API faked in [tests/mocks.lua](tests/mocks.lua). [tests/SPEC.md](tests/SPEC.md) describes the behaviour they check. The script exits with 1 if the check reports an error or a test fails. Rendering, animations, sounds and multiplayer sync need the in-game tests in [tests/MANUALTESTS.md](tests/MANUALTESTS.md).

#### Deploying

```powershell
.\deploy_local.ps1            # copies the mod to %UserProfile%\Zomboid\Workshop\pass-out
.\deploy_local.ps1 -Undeploy  # removes it again
```

The game lists the deployed copy as a local mod. The general debug tools, reload behaviour and log files are described in the toolkit's [MODDING.md](https://github.com/drandarov-io/project-zomboid-mod-toolkit/blob/master/MODDING.md#testing-in-debug-mode).

#### Testing on Build 42

The in-game tests, their setup and the debug tools they use are in [tests/MANUALTESTS.md](tests/MANUALTESTS.md).

#### Publishing

`workshop/workshop.txt` holds the Workshop item ID (2850167382), title, description, tags and visibility. Every upload replaces the title, description, tags, visibility and preview image of the Workshop page with these values, so edit them there and not in the uploader: the uploader only writes to the deployed copy, which the next deploy overwrites. Tags not listed in the game's `media/WorkshopTags.txt` are dropped.

1. Raise `modversion` in `42/mod.info`, and in `workshop/mod.info` when the Build 41 version changed.
2. Run `.\test.ps1`, then `.\deploy_local.ps1`.
3. Start the game through Steam. `-debug` isn't needed.
4. Main menu, WORKSHOP, Create and update items, select `pass-out`, Next.
5. Check the details read from `workshop.txt`, Next.
6. Edit Change Notes, then Upload to Steam Workshop now!.

The uploader's pages and validation rules are in the toolkit's [Publishing to the Workshop](https://github.com/drandarov-io/project-zomboid-mod-toolkit/blob/master/MODDING.md#publishing-to-the-workshop).
