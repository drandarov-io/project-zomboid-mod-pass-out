# Manual tests on Build 42

[pass_out_spec.lua](pass_out_spec.lua) checks the rules in [SPEC.md](SPEC.md) against a faked game. These tests check what only the running game shows: rendering, animations, sounds, character creation, split-screen and multiplayer. Build 41 (`media/`) is not covered.

Run [Setup](#setup) once, then the tests in order. Test 1 creates the save the others use.

## Setup

### Game

1. Add `-debug` to the game's Steam launch options (Properties, General, Launch Options).
2. Run `.\deploy_local.ps1` in the repository root.
3. Start the game and open Mods on the main menu.

   Expect: Pass out is listed with the Workshop preview image as its icon.

4. Enable Pass out.

### Test save

[1. Traits at character creation](#1-traits-at-character-creation) creates a sandbox save with these values on the Pass Out page. All other options stay at their defaults.

| Option | Test value | Effect |
|--------|------------|--------|
| Pass Out Hours | 0 | The warning shows on the first in-game minute at the required tiredness, the blackout starts on the next |
| Pass Out Randomness | 0 | No random offset |
| Passing Out Minutes | 5 | The fade lasts 5 in-game minutes. With 1 the collapse follows in the same minute the blackout starts |

### Debug tools

The debug menu is the bug icon in the in-game sidebar. The Lua console opens with the `` ` `` key. Trait registration writes `[PassOut]` lines to `%UserProfile%\Zomboid\console.txt`.

| Tool | Where | Use for this mod |
|------|-------|------------------|
| Fatigue slider | General debuggers, Body tab | 0 to 1. Above 0.9 is Exhausted, the default Required Tiredness Level. Above 0.8 is Very Tired, above 0.7 Tired. Console: `getPlayer():getStats():set(CharacterStat.FATIGUE, 1)` |
| Panic slider | General debuggers, Body tab | 0 to 100. Above 6 shows the panic moodle, which triggers the panic save. Console: `getPlayer():getStats():set(CharacterStat.PANIC, 100)` |
| Game Speed slider | General debuggers, Game tab | Speeds up the countdown, which compares game timestamps and stays exact. The fade and panic saves advance once per `EveryOneMinute` call, which fires at most once per frame, so at high speeds they last more in-game minutes. Set the speed back to 1 before the blackout |
| Invisible | Cheats | Keeps zombies away while waiting. Leave God Mode off: it resets fatigue on every update and the countdown never starts |
| Add Trait | Player's Stats | Adds a trait to the running character. Resistant To Passing Out is listed with "Good Trait" ticked, Prone To Passing Out with it unticked. Remove next to a trait icon removes it |
| Sandbox Settings | Debug menu | Changes the Pass Out options of the running game. After Apply, run `getSandboxOptions():toLua()` in the console, otherwise the mod still reads the old values. For a quick test, `SandboxVars.PassOut.<key> = <value>` takes effect on the next in-game minute but isn't saved. The keys are in [SPEC.md](SPEC.md#sandbox-options) |
| Countdown state | Lua console | `local md = getPlayer():getModData(); print(md.poTiredTime, md.poRandomnessValue, md.poWarned, md.poPhase, md.poPassOutFactor)`. `poTiredTime` is the game timestamp when the countdown started, `poPhase` is `passing` during the fade |

### After a code change

Run `.\deploy_local.ps1`, quit to the main menu and load the save again. Do not use the per-file reload of the debug Lua file browser: it runs `Pass_Out.lua` again on top of the loaded copy and doubles its event handlers.

### Before each test

1. If a fade is running, let it end in the collapse, and wait until the character is awake. Lowering fatigue does not stop a fade.
2. Set Fatigue to 0 and wait one in-game minute.
3. Set Game Speed to 1.
4. Print the countdown state.

   Expect: all five values are `nil`.

## Tests

### 1. Traits at character creation

1. Start a new sandbox game with Enable Pass Out off and go on to the character creation.

   Expect: neither Prone To Passing Out nor Resistant To Passing Out is in the trait lists.

2. Start another new sandbox game with Enable Pass Out on and the [test save](#test-save) values, and go on to the character creation.

   Expect: Prone To Passing Out (gives 4 points) and Resistant To Passing Out (costs 4 points) are listed.

3. Choose one of the two traits.

   Expect: the other one is removed from the available traits.

4. Remove the chosen trait again, start the game without a Pass Out trait and turn on Invisible.

### 2. Collapse

1. Set Fatigue to 1.

   Expect: on the next in-game minute, "You are about to start passing out..." shows as halo text above the character.

2. Wait one in-game minute.

   Expect: the character says "You are passing out..." and the screen starts to blur, lose colour and darken.

3. Wait 5 in-game minutes.

   Expect: the character sits down on the ground and falls asleep, the screen fades out and time speeds up.

4. Wait until the character wakes.

   Expect: the character stands up and the screen is normal.

### 3. Panic save

1. Set Panic to 100.
2. Set Fatigue to 1.

   Expect: the warning and the blackout as in [2. Collapse](#2-collapse). Panic does not hold the countdown.

3. Wait until the fade is complete.

   Expect: the screen stays dark and the character says "Panic is keeping you awake..." every in-game minute. Each time, Panic drops by 10 on top of its normal decay.

4. Wait until the panic moodle is gone.

   Expect: the character collapses as in [2. Collapse](#2-collapse).

### 4. Trait timing

Set Pass Out Hours to 1 with `SandboxVars.PassOut.passOutHours = 1`. Randomness 0 and Passing Out Minutes 5 come from the test save. Do one run per row:

| Run | Trait | Blackout after Fatigue 1 | Fade |
|-----|-------|--------------------------|------|
| a | None | About 60 in-game minutes | 5 in-game minutes |
| b | Prone To Passing Out | About 48 in-game minutes | 3 in-game minutes |
| c | Resistant To Passing Out | About 72 in-game minutes | 8 in-game minutes |

1. In Player's Stats, remove the trait of the previous run and add the trait of this run.
2. Do [Before each test](#before-each-test).
3. Set Fatigue to 1, note the in-game time and raise Game Speed.
4. When "You are about to start passing out..." shows, set Game Speed back to 1.
5. Wait for "You are passing out...".

   Expect: the time since step 3 matches the Blackout column, and the warning came about 10 in-game minutes before.

6. Wait for the collapse.

   Expect: the time since step 5 matches the Fade column.

After run c, remove the trait and run `SandboxVars.PassOut.passOutHours = 0`.

### 5. Death during the fade

1. Type `getPlayer():Kill(nil)` in the console without running it.
2. Set Fatigue to 1 and wait for "You are passing out...".
3. During the fade, run the command.
4. Respawn with a new character.

   Expect: the screen is normal.

5. Turn foraging search mode on and off.

   Expect: it shows and hides as without the mod.

### 6. Driving

Use a car with a horn and a charged battery, on an open road.

1. Drive, set Fatigue to 1 and keep driving.

   Expect: the warning and the blackout as in [2. Collapse](#2-collapse).

2. Keep driving until the fade is complete.

   Expect: the character falls asleep at the wheel, the horn sounds without a break and the car rolls on.

3. Wait until the character wakes.

   Expect: the horn stops.

4. Run `SandboxVars.PassOut.hornWhilePassedOut = false`, do [Before each test](#before-each-test) and repeat steps 1 and 2.

   Expect: the car rolls on, but the horn stays silent.

5. Run `SandboxVars.PassOut.hornWhilePassedOut = true` and `SandboxVars.PassOut.passOutWhileDriving = false`. Do [Before each test](#before-each-test), then drive and set Fatigue to 1.

   Expect: the warning shows, but no blackout starts while you drive.

6. Stop and leave the driver seat.

   Expect: "You are passing out..." on the next in-game minute.

7. Run `SandboxVars.PassOut.passOutWhileDriving = true`.

### 7. Split-screen

1. Press A on a second controller to add a second player.
2. Run `getSpecificPlayer(0):getStats():set(CharacterStat.FATIGUE, 1)`.

   Expect: only the first player gets the warning, the fade and the collapse. The second player's screen stays normal.

3. While the first player is asleep, move them.

   Expect: they stay asleep for Forced Pass-Out Duration, 30 real seconds by default. After that, moving wakes them.

4. Do [Before each test](#before-each-test) for both players, then set Fatigue to 1 for both with `getSpecificPlayer(0)` and `getSpecificPlayer(1)`.

   Expect: each player gets their own warning, fade and collapse.

### 8. Multiplayer

1. Host from a `-debug` game. In the server settings, add the mod on the Mods page and turn on `SleepAllowed` and `SleepNeeded` on the Players page.
2. Join and create a character.

   Expect: both Pass Out traits are listed.

3. Set Fatigue to 1.

   Expect: the warning, the blackout and the collapse as in [2. Collapse](#2-collapse).

4. While asleep, press a movement key.

   Expect: the character stays asleep for Forced Pass-Out Duration. After that, moving wakes them.

5. If a second client is connected, watch the collapse from there.

   Expect: the collapsed player sits on the ground and stands up on waking.

6. Restart the server with `SleepAllowed` or `SleepNeeded` off and create a new character.

   Expect: the Pass Out traits are not listed, and Fatigue 1 starts no countdown.
