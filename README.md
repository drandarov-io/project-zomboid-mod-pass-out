# Pass out

Causes your character to fall asleep on the spot if you have max tiredness for X in-game hours (default 6). The amount of hours, whether a warning is given, and collapse behavior are configurable in the sandbox options.

This is intended for a more hardcore playthrough.

Dual-build compatible with **Build 42** (primary) and **Build 41** (backport).

---

### Features:

- **Build 42 & Build 41 Dual Support**:
  - `42/` subfolder structure with versioned `mod.info`, B42 APIs (`CharacterStat.PANIC`, `MoodleType.TIRED`), and `.json` translations.
  - Root `media/` backport preserving Build 41 legacy APIs and `.txt` translations.
- **Traits**:
  - **Prone to Passing Out** (+4 trait points / negative): More susceptible to passing out (20% less time before collapse, 50% faster blackout fade, panic save drains 20 points/min).
  - **Resistant to Passing Out** (-4 trait points / positive): Fights off unconsciousness longer (20% more time before collapse, 50% longer blackout fade, panic save drains only 5 points/min).
  - Mutually exclusive, full B42 registry scripts + B41 `TraitFactory` support, custom 18x18 trait icons included.
- **Collapse Animation (Build 42)**:
  - Your character sinks to the ground (`sitonground`) when passing out instead of standing bolt upright with open eyes, and stands back up on waking (`forceGetUp`).
  - Mirrored onto remote sleepers in multiplayer.
- **Multiplayer & Split-Screen**:
  - Fully compatible with dedicated servers and split-screen couch co-op.
  - Movement lockout prevents the common MP instant-wake glitch where a held movement key would immediately cancel the collapse.
- **Vehicle Support**:
  - Slumping over the wheel honks the car horn and lets the car roll on until you stop or wake up.
  - Toggleable via sandbox options.
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
| Pass Out While Driving | on | Drop at the wheel: car keeps rolling and you slump onto the horn. |

---

### Thumbnail
![Thumbnail](workshop/poster.png)

### Credits
- Original mod & concept by **DahakaMVl** (Dmitrij Drandarov)
- Build 42 port, traits, collapse animations & multiplayer fixes by **turnip**
