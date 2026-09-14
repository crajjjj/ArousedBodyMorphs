# Aroused BodyMorphs

Skyrim SE mod by crajjjj (inspired by the ArousedNips family of mods).
Drives BodyMorph sliders on nipples/areolas/vagina in proportion to an actor's
SexLab Aroused arousal value (0 = no morph, 100 = full effect, linear in
between). Dev repo layout: sources and project files at the root, `dist\` is
the installable mod (MO2-ready). GitHub: https://github.com/crajjjj/ArousedBodyMorphs

## Build

**Do NOT compile.** The user compiles Papyrus themselves. Edit `.psc` sources
under `dist\source\scripts\` and stop. Verify correctness by reading the code.

If the user asks how to build, they use `PapyrusCompiler.exe` with
`skyrimse.ppj` (e.g. via Caprica / pyro / the Creation Kit). The PPJ writes
`.pex` output to `dist\scripts\` and produces a release zip under `Release\`
(zip root = `dist\`) when `Zip="true"`.

## Bumping the Version

Three places hold the version — keep in sync:

1. **`dist\meta.ini`** — `version=1.0.0`. MO2 reads this; canonical user-facing version.
2. **`ABM_ConfigMenu.psc`** — `GetVersion()` returns `(M)MmmPP` (10000 = 1.00.00). Recompile to `.pex` after editing.
3. **`dist\ReadMe_ArousedBodyMorphs.txt`** — top-of-file version line and changelog entry.

Release marker: git tags (see global instructions — don't double-bump an
untagged version).

## Project Layout

```
dist\ArousedBodyMorphs.esp       Plugin (ESL-flagged ESP, records 0x800-0x803)
dist\ReadMe_ArousedBodyMorphs.txt User-facing readme + changelog
dist\meta.ini                    Mod Organizer 2 metadata
dist\source\scripts\*.psc        Papyrus source (4 scripts)
dist\scripts\*.pex               Compiled bytecode
dist\SKSE\...\ArousedBodyMorphs\ Intensity presets + sample morph.json
skyrimse.ppj                     Papyrus project (compile + zip config)
```

### Scripts

| Script | Role |
|--------|------|
| `ABM_Quest` | Hosts mod state: morph names, max-value sliders, defaults, flags, area-group helpers (`GroupForMorph` / `GroupName`). `OnInit()` runs first-time setup. |
| `ABM_PlayerAlias` | `ReferenceAlias` on the player. Detects NiOverride/SKEE, identifies the SLA flavor, runs `UpdateActor()` to push BodyMorph values, owns the player poll, under-armor suppression and the reveal tween. NIO key is `"ArousedBodyMorphs.esp"`. |
| `ABM_ConfigMenu` | SkyUI MCM (two pages: General / Morphs). Morphs page groups sliders by area (Nipples / Areolas / Vagina / Other) via `GroupForMorph`, split across both columns at the row midpoint. JSON import/export via `JsonUtil` (`ArousedBodyMorphs/config.json`, `ArousedBodyMorphs/morph.json`). |
| `ABM_DebugSpellEffect` | Lesser-power magic effect. Dumps actor base + morph values to the Papyrus log, forces `UpdateActor()`, dumps again. |

### ESP records (all defined by this plugin, ESL range)

| FormID | Type | EditorID | Notes |
|--------|------|----------|-------|
| 0x800 | MagicEffect | `ABM_DebugSpellEffect` | Script archetype; script `ABM_DebugSpellEffect`, property `PlayerAlias` → quest 0x802 alias 0 |
| 0x801 | Spell | `ABM_DebugSpell` | Lesser power, effect → 0x800 |
| 0x802 | Quest | `ABM_MainQuest` | RunOnce, NOT start-game-enabled (started by the MCM's `OnConfigRegister`). Player alias 0 with script `ABM_PlayerAlias` (props: `MainQuest`, `sla_Framework`, `SexLabQuestFramework`); quest script `ABM_Quest` (prop `PlayerAlias`) |
| 0x803 | Quest | `ABM_ConfigMenuQuest` | StartGameEnabled + RunOnce. Script `ABM_ConfigMenu` (props: `ModName`="Aroused BodyMorphs", `MainQuest`, `DebugSpell`); alias 0 carries SkyUI's `SKI_PlayerLoadGameAlias` |

Masters: Skyrim.esm, Update.esm, SexLab.esm, SexLabAroused.esm.

### Hard Dependencies

| Dep | Provides | Reference path on this machine |
|-----|----------|---------------------------------|
| SexLab Aroused (NG / OSL stub / legacy) | `slaFrameworkScr` | `C:\Playground\Skyrim\mods\SKSE\SexlabArousedNG` (canonical reference; PPJ imports its `dist\Core\Source\Scripts`) |
| SexLab Framework | `SexLabFramework` | `C:\Playground\Skyrim\mods\build\Sexlab\scripts\Source` |
| RaceMenu / NiOverride (SKEE) | BodyMorph API, `StringUtil` | `C:\Playground\Skyrim\mods\build\racemenu\scripts\source` |
| PapyrusUtil | `JsonUtil`, `MiscUtil` | `C:\Playground\Skyrim\mods\build\PapyrusUtil\Source\Scripts` |
| SkyUI | `SKI_ConfigBase` (MCM) | `C:\Playground\Skyrim\mods\build\SkyUI_5.1_SDK\Scripts\Source` |

#### SLA flavor detection (multi-fork)

Follows the **"Supporting Both OSL Aroused and SLA NG"** pattern from
`SexlabArousedNG/README.md`. `ABM_PlayerAlias.OnPlayerLoadGame` calls
`sla_Framework.GetVersion()` and branches on the date-stamped scheme:

| `GetVersion()` | Fork | Flag set | Read path |
|---|---|---|---|
| `>= 20200000` | SexLab Aroused NG / SLO Aroused NG (3.x, packs `MMmmppp`) | `isSLAroused29 = true` | `GetActorArousal` — full recalculation per call |
| `> 0` and `< 20200000` | OSL Aroused stub (`20140124`), SLAXSE2022 (`20190720`), eXtended LE, SSELoose | `isSLAroused28 = true` ("Legacy / OSL stub") | `GetActorArousal` works on the stub too |
| `0` | Nothing installed | both flags `false` | abort with notification |

Why `GetActorArousal` and not the `slaArousal` faction rank: the faction rank
is a *cache* SLA only refreshes on its scan tick (default 120s);
`GetActorArousal` triggers a fresh recalculation on every call — required for
the poll loop to be useful.

#### Player poll (mid-scene responsiveness)

SLA NG only broadcasts `sla_UpdateComplete` at the end of its periodic scan
(default 120s). The alias runs its own player-only poll via `OnUpdate()`:
re-arms each tick via `RegisterForSingleUpdate(PollInterval)` (default 5s,
MCM 0–60s; 0 disables). NPCs refresh only on the heartbeat
(`OnArousalComputed`). `RestartPolling()` is called from the MCM after the
slider changes. `SexLab StageStart` is a separate path with an immediate `+50`
morph bump per stage.

A BodySlide-compatible body/armor with morph data generated is required for
the effect to be visible in-game (user-side concern, not a code concern).

## Papyrus Language Notes

### Control flow
- No `break` or `continue` — use flags or early `return` to exit loops.
- Only `if/elseif/else/endif` and `while/endwhile`. No for-loops, switch, or do-while.
- Logical `||` and `&&` short-circuit.

### Variables & types
- Five base types: `Bool`, `Int`, `Float`, `String`, plus object references and arrays.
- Value types copied on assignment; objects/arrays are by reference.
- **Locals are function-scoped, not block-scoped.** Declaring the same name in sibling `if` branches is a compile error — hoist the declaration above the branches.
- Variables inside `while` loops persist across iterations (NOT reset each iteration). Initialize explicitly.
- Script-level variables can only be initialized with literals; function-level can use expressions.

### Arrays
- Max 128 elements. Size must be an integer literal (`new float[4]`), not a variable.
- `array[i] += 5` does NOT compile — use `array[i] = array[i] + 5`.
- No arrays of arrays. Passed/assigned by reference.
- String `==`, `Find()`/`RFind()` and the SKSE string functions are all case-insensitive (the engine interns strings case-insensitively).

### States
- Script can be in only one state at a time. `GotoState("")` returns to empty state.
- State function signatures must exactly match the empty-state definition.
- State transitions fire `OnEndState()` → change → `OnBeginState()`.

### Threading
- Only one thread can run a script instance at a time. Any external call (including `Debug.Trace()`, property access on other objects) unlocks the script, allowing other threads in.
- After an external call returns, local assumptions about script state may be stale.

### Misc gotchas
- Compiler does not check all code paths for return values — missing returns cause undefined behavior.
- `parent.FunctionName()` calls one level up, not necessarily the base definition.
- Unary minus can misbehave without spaces: write `x = y - 1` not `x = y-1`.
- CK-filled properties (set in the plugin) must NOT be removed from `.psc` files even if unused — removing them breaks the form binding. To clean up, also clear the property in the plugin.

## Code Conventions

- Papyrus source: `dist\source\scripts\*.psc`. Compiled: `dist\scripts\*.pex`. Both folders are flat — no subdirectories.
- Keep edits ASCII unless the file already contains non-ASCII.
- Runtime JSON (`ArousedBodyMorphs/config.json`, `ArousedBodyMorphs/morph.json`) lives in `Data\SKSE\Plugins\StorageUtilData\` — the shipped copies under `dist\SKSE\` are the install defaults. All values stored as strings; readers cast to `int`/`float`, writers must do `(value as int) as string` explicitly.
- Preset/morph JSON keys use the EXACT morph names from `ABM_Quest.FullMorphSet()` (mixed case) — no normalization layer exists; keep them in sync.
- JsonUtil API quick-reference: `StringListClear/Count/Get/Add(file, listKey, ...)`, `GetStringValue(file, key, missing)` (third arg positional), `SetStringValue(file, key, value)`.
- Papyrus does not support named arguments in the stock CK compiler. Always use positional args.

## Commit Conventions

- **Never include a `Co-Authored-By: Claude ...` trailer** in commit messages. Commits should look authored solely by the human user.
- One-line summaries, imperative mood; body only when the *why* would be lost.
