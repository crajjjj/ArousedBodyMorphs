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

The same applies to the native DLL: edit C++ under `native\src\` and stop —
the user builds it (`cd native && xmake f -m release && xmake`; deploys to
`dist\SKSE\Plugins`). Only build when explicitly asked.

## Native layer (`native\`, optional ArousedBodyMorphs.dll)

Event-driven replacement for the Papyrus update pipeline; see
[native/README.md](native/README.md). Key invariants:

- Backends resolved at runtime, never linked: `SexlabArousedNG.dll` →
  `SLA_GetArousalInt` (C API; poll + `sla_UpdateComplete` sweep), or
  `OSLAroused.dll` → `GetArousalExt` + `OSLA_ActorArousalUpdated` mod events
  (fully event-driven). Neither present → DLL idles, Papyrus path runs.
- Morph writes via SKEE's `IBodyMorphInterface` (messaging handshake to
  "skee"), same NIO key `ArousedBodyMorphs.esp` as the Papyrus path.
- Papyrus is the settings owner: `ABM_PlayerAlias.PushConfigToNative()`
  mirrors options + morph table into the DLL (called from OnPlayerLoadGame,
  SetModEnabled, RestartPolling, MCM OnConfigClose). The DLL persists nothing.
- **Every `ABM_Native.*` call in Papyrus must be gated** by
  `ABM_Native.IsInstalled()` (SKSE plugin query) — the natives are unbound
  without the DLL. `ABM_PlayerAlias.NativeActive()` is the combined gate
  (cached per load via `ResolveNativeMode()` — a DLL install/uninstall needs a
  game restart, so never re-probe per actor); all Papyrus pipeline paths
  (poll, heartbeat, armor events, UpdateActor) stand down when it is true.
- **Threading contract (CTD-critical):** `MorphApplier::UpdateActor` /
  `ClearActor` do direct SKEE geometry work (`ApplyBodyMorphs`) and are MAIN
  THREAD ONLY — reach them via `SKSE::GetTaskInterface()->AddTask`. The
  Papyrus bindings use the `*Deferred` variants (evaluate inline for the
  return code, queue the SKEE write); never bind the direct ones to Papyrus.
  Event sinks only classify + queue, and bursty sources (heartbeat, equip)
  coalesce through an `exchange(true)` pending flag.
- **Unchanged-value skip:** both pipelines skip the morph writes + model
  rebuild when the values are already applied. Every slot is
  `maxValue[i] * factor` with exactly TWO factors in play - `arousal/100 *
  armorScale` for the morphs `suppress.json` covers, and `arousal/100` for
  the rest - so ONE PROBE PER FACTOR settles it: read the first non-zero-max
  morph of each class back under our key (`NiOverride.GetBodyMorph` /
  `IBodyMorphInterface::GetMorph`) and compare to its target, tolerance 1e-6.
  A single probe was enough only while one factor covered the whole table;
  with a mixed flag set it misses every change confined to the other factor
  (bare <-> covered while the probe sits in an unsuppressed morph), so do not
  collapse it back. When `armorScale == 1.0` the two factors coincide and the
  flags are not even read.
  **Deliberately no cache** - SKEE is the single source of truth, so nothing
  needs invalidating on a settings push, a save load, or an external clear,
  and the comparison targets move with the settings by construction. Do not
  "optimize" this back into a remembered value: the probes are one or two
  calls against 23 writes plus a mesh rebuild, and every cached variant of
  it grew a staleness bug.
- **What under-armor suppression covers is DATA, not an option:**
  `suppress.json` (StorageUtilData, beside config/morph.json) holds one
  `"suppress"` string list whose entries are either an exact morph name or an
  area keyword (nipples / areolas / vagina / other, matched through
  `GroupForMorph`, which is the one-liner for a body whose sliders aren't
  listed). Ships as the 21 nipple + areola sliders of 3BA, UBE and BHUNP,
  deduped - one file for every body, since a name the active table doesn't
  contain is simply never looked up. Nothing below the chest: the trigger is
  a CHEST test, so it says nothing about a vagina slider, which a skimpy
  armor leaves on show anyway. Keep it in step when a body patch adds a chest
  slider; UBE's erection morph is `AreolaErection`, NOT a nipple name, so an
  areola-free list would let it inflate through tops. The MCM keeps a single
  on/off toggle; widening or narrowing the set is a file edit. Deliberately
  ONE reader: `ABM_Quest.RebuildMorphTables()` resolves the file into
  `MorphSuppressed[]` (1 per slot) on every table change (`ResetDefaults`,
  so Import re-reads it) and every `OnPlayerLoadGame`, and `PushSuppressFlags`
  hands those flags to the DLL - which never parses JSON - while the writer
  only indexes an array. That push is a separate native, called LAST, purely
  so a scripts-only update onto a pre-1.1.0 DLL degrades to its old behaviour
  instead of leaving it with no morph table at all. A missing file or an empty
  list falls back to the `nipples` keyword: deleting it must not silently
  switch suppression off and let nipples clip through tops. To suppress
  nothing, use the toggle.
- **Creature test:** a race without the `ActorTypeNPC` keyword is a creature,
  in BOTH pipelines. `ActorBase.GetSex()` returns only -1/0/1
  (None/Male/Female) — the folkloric 2/3 creature codes do not exist; never
  reintroduce a `sex == 2/3` beast filter.
- **"Top covered" test:** the `ArmorCuirass` / `ClothingBody` keyword check
  scans **every worn item**, in BOTH pipelines (`Actor.WornHasKeyword` in
  Papyrus; one `GetInventory` walk over worn armor in the DLL). 1.0.5 narrowed
  it to the slot-32 item to drop corsets/piercings that merely inherited
  `ClothingBody`, and that was wrong: in a real load order ~59 bras and tops sit
  on slot 56 and ~65 on slot 46 with slot 32 empty, so they stopped suppressing
  and inflated through the armor. SLA NG agrees — `slamainscr.
  IsActorNakedExtended` checks slot 32 and then seven auxiliary slots (44, 45,
  48, 49, 52, 56, 58). Do not re-narrow it to one slot.
- Advanced Nudity Detection is the OVERRIDE on top of that (covered → bare),
  on any of Nude `0x831` / Topless `0x832` / ShowingChest `0x82F` at rank 1.
  **AND ships ESL-flagged**, so `Game.GetModByName("Advanced Nudity Detection.
  esp")` returns 255 and must never guard the resolve — that was the 1.0.5 bug
  that left `AND_Resolved` false and the whole override dead. `GetFormFromFile`
  resolves light plugins fine, so a non-None faction IS the install test. The
  DLL is unaffected: CommonLib's `LookupFormID` handles `compileIndex == 0xFE`
  and folds in `smallFileCompileIndex << 12`.
  ShowingChest is AND's "Showing Breasts" — it catches an open-front or skimpy
  top AND the inherited-keyword accessories, since both leave the breasts
  visible, so it must stay in the set. Without AND those accessories read as a
  top again; that is the accepted trade.
- CommonLibSSE-NG vendored as submodule at `native\lib\commonlibsse-ng`
  (alandtse fork, `ng` branch, currently v8.0.1).

## MCM init weight

SkyUI registers EVERY installed MCM in one pass, so anything slow in
`OnConfigInit` / `OnConfigRegister` is charged against that pass -- which is how
a menu ends up lagging or never registering at all on a new game. Reference
implementation: SL Widgets' `slw_menu.psc` sets `ModName` plus one notification
and nothing else, builds `Pages` in `OnConfigOpen`, and leaves every
cross-script read to `OnPageReset`.

Ours follows that:
- Both registration hooks are a trace plus page setup. No notifications, no
  cross-script reads, no setup work.
- `ABM_MainQuest` is Start Game Enabled, so the engine starts the mod
  independently of SkyUI (the MCM `Start()` call is a legacy-save fallback).
- `ABM_Quest.OnInit` splits itself: its own tables inline, and everything that
  reaches outside the script (framework lookup, NiOverride probe, AND form
  resolves, mod events, poll, native push) deferred to `OnUpdate` a second
  later. `ResetAllState` keeps the synchronous path for the MCM's Reset button.
- The derived tables are rebuilt ONCE per load, in `OnPlayerLoadGame`. Do not
  add a second rebuild elsewhere -- `ResolveSlaFlavor` used to carry one, and on
  the retry path it fired up to a minute later for no gain.

## Bumping the Version

Four places hold the version — keep in sync:

1. **`dist\meta.ini`** — `version=`. MO2 reads this; canonical user-facing version.
2. **`ABM_ConfigMenu.psc`** — `GetVersion()` returns `(M)MmmPP` (10000 = 1.00.00). Recompile to `.pex` after editing.
3. **`dist\ReadMe_ArousedBodyMorphs.txt`** — top-of-file version line.
4. **`native\xmake.lua`** - `set_version(...)`, the DLL's own version resource.
   Only matters when the DLL is rebuilt, but it says "keep in step" for a
   reason: it is what `SKSE.GetPluginVersion` reports.

The readme carries NO changelog: this is a pre-release mod, so per-version
history is noise. Release notes live on the GitHub release instead.

Release marker: git tags (see global instructions — don't double-bump an
untagged version).

## Project Layout

```
dist\ArousedBodyMorphs.esp       Plugin (ESL-flagged ESP, records 0x800-0x803)
dist\ReadMe_ArousedBodyMorphs.txt User-facing readme + changelog
dist\meta.ini                    Mod Organizer 2 metadata
dist\source\scripts\*.psc        Papyrus source (5 scripts)
dist\scripts\*.pex               Compiled bytecode
dist\SKSE\...\ArousedBodyMorphs\ Intensity presets + sample morph.json
skyrimse.ppj                     Papyrus project (compile + zip config)
native\                          Optional SKSE DLL (xmake + CommonLibSSE-NG)
```

### Scripts

| Script | Role |
|--------|------|
| `ABM_Quest` | Hosts mod state: morph names, max-value sliders, defaults, flags, area-group helpers (`GroupForMorph` / `GroupName` / `GroupKeyword`) and the resolved under-armor set (`RebuildMorphTables` / `MorphSuppressed` / `UnderArmorActive`). `OnInit()` runs first-time setup. |
| `ABM_PlayerAlias` | `ReferenceAlias` on the player. Detects NiOverride/SKEE, identifies the SLA flavor, runs `UpdateActor()` to push BodyMorph values, owns the player poll, under-armor suppression and the reveal tween. NIO key is `"ArousedBodyMorphs.esp"`. |
| `ABM_ConfigMenu` | SkyUI MCM (two pages: General / Morphs). Morphs page groups sliders by area (Nipples / Areolas / Vagina / Other) via `GroupForMorph`, split across both columns at the row midpoint. JSON import/export via `JsonUtil` (`ArousedBodyMorphs/config.json`, `ArousedBodyMorphs/morph.json`). |
| `ABM_DebugSpellEffect` | Lesser-power magic effect. Dumps actor base + morph values to the Papyrus log, forces `UpdateActor()`, dumps again. |
| `ABM_Native` | Global bindings for the optional native DLL (`IsInstalled` gate + natives: `IsActive`, `GetBackendName`, `UpdateActor`, `ClearActorMorphs`, `PushConfig`, `PushMorphTable`, `PushSuppressFlags`). No form binding — not in the ESP. |

### ESP records (all defined by this plugin, ESL range)

| FormID | Type | EditorID | Notes |
|--------|------|----------|-------|
| 0x800 | MagicEffect | `ABM_DebugSpellEffect` | Script archetype; script `ABM_DebugSpellEffect`, property `PlayerAlias` → quest 0x802 alias 0 |
| 0x801 | Spell | `ABM_DebugSpell` | Lesser power, effect → 0x800 |
| 0x802 | Quest | `ABM_MainQuest` | StartGameEnabled + RunOnce (DNAM flags `0x0101`). The ENGINE starts it, so the mod comes up without SkyUI; the MCM's `MainQuest.Start()` is only a recovery line for pre-1.1.1 saves whose MCM never registered. Player alias 0 with script `ABM_PlayerAlias` (props: `MainQuest`, `sla_Framework`); quest script `ABM_Quest` (prop `PlayerAlias`) |
| 0x803 | Quest | `ABM_ConfigMenuQuest` | StartGameEnabled + RunOnce. Script `ABM_ConfigMenu` (props: `ModName`="Aroused BodyMorphs", `MainQuest`, `DebugSpell`); alias 0 carries SkyUI's `SKI_PlayerLoadGameAlias` |

Masters: Skyrim.esm, Update.esm, SexLabAroused.esm. (Deliberately NOT
SexLab.esm — the mod must load on OStim-only setups; keep it that way.)

### Hard Dependencies

| Dep | Provides | Reference path on this machine |
|-----|----------|---------------------------------|
| SexLab Aroused (NG / OSL stub / legacy) | `slaFrameworkScr` | `C:\Playground\Skyrim\mods\SKSE\SexlabArousedNG` (canonical reference; PPJ imports its `dist\Core\Source\Scripts`) |
| RaceMenu / NiOverride (SKEE) | BodyMorph API, `StringUtil` | `C:\Playground\Skyrim\mods\build\racemenu\scripts\source` |
| PapyrusUtil | `JsonUtil`, `MiscUtil` | `C:\Playground\Skyrim\mods\build\PapyrusUtil\Source\Scripts` |
| SkyUI | `SKI_ConfigBase` (MCM) | `C:\Playground\Skyrim\mods\build\SkyUI_5.1_SDK\Scripts\Source` |

#### SLA flavor detection (multi-fork)

Follows the **"Supporting Both OSL Aroused and SLA NG"** pattern from
`SexlabArousedNG/README.md`. `ABM_PlayerAlias.ResolveSlaFlavor` (from
`OnPlayerLoadGame`) calls `sla_Framework.GetVersion()` and branches on it:

| `GetVersion()` | Fork | Flag set | Read path |
|---|---|---|---|
| `>= 20200000` | SexLab Aroused NG, published as SLO Aroused NG -- one mod, not two (3.x, packs `MMmmppp`) | `isSLAroused29 = true` | `GetActorArousal` — full recalculation per call |
| `> 0` and `< 20200000` | OSL Aroused stub (`20140124`), SLAXSE2022 (`20190720`), eXtended LE, SSELoose | `isSLAroused28 = true` ("Legacy / OSL stub") | `GetActorArousal` works on the stub too |
| `0`, quest present | Fork installed but not initialized yet | unchanged, retry pending | see below |
| `0`, no `sla_Framework` quest | Nothing installed | both flags `false` | abort with notification |

**`GetVersion() == 0` is not "missing" - never abort on it** (the 1.0.6 bug).
SLA NG answers out of `slaMainScr`'s **save-persisted** `modVersion`, and that
stays 0 until its own init has run once:
`slaInternalScr.OnInit` arms +5s, `Maintenance()` enters the `initializing`
state and arms +10s, and only that tick calls `SetVersion`. Our
`OnPlayerLoadGame` fires in the first second of the load, so on the **first**
session after installing that fork we read 0 and switched the mod off for the
whole session, recovering only after another save + reload. Forks that return
a literal (OSL Aroused `20140124`, SLAXSE2022 `20190720`) never showed it,
which is why it read as fork-specific. `ResolveSlaFlavor` therefore retries on
`RegisterForSingleUpdate` (`SLA_RETRY_INTERVAL` 5s x `SLA_RETRY_MAX` 12, ~60s
of cover) and, if the version never arrives, falls back to the legacy flag
rather than aborting - the quest object resolved, so `GetActorArousal` is
there. The retry borrows the alias's `OnUpdate` slot, which the poll has not
claimed yet; `RestartPolling` re-arms the retry instead of the poll while one
is pending. The DLL picks its own backend by DLL export, so it never misread
the version - but the abort skipped `PushConfigToNative()` too, so native
mode went unconfigured for that session as well.

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
slider changes. (The ancestor mod's SexLab `StageStart` +50 morph bump was
removed with the SexLab.esm master; mid-scene response comes from the poll /
OSL events instead.)

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
- Keep edits ASCII unless the file already contains non-ASCII. `dist\Interface  Translations\*.txt` are the deliberate exception: they are UTF-16 LE **with
  BOM**, CRLF, `$key<TAB>text`, and carry real diacritics / Cyrillic / CJK.
  `.gitattributes` marks them `-text` so no line-ending conversion touches them.
  The filename stem is the **plugin** name (`ArousedBodyMorphs`), NOT the MCM's
  `ModName` -- SkyUI keys the lookup off the data file. Every language file must
  hold the identical key set; SkyUI only substitutes on a WHOLE-string match, so
  a label built by concatenation (title + version, the morph count) cannot be
  translated and is deliberately left literal.
- Runtime JSON (`ArousedBodyMorphs/config.json`, `ArousedBodyMorphs/morph.json`, `ArousedBodyMorphs/suppress.json`) lives in `Data\SKSE\Plugins\StorageUtilData\` — the shipped copies under `dist\SKSE\` are the install defaults. All values stored as strings; readers cast to `int`/`float`, writers must do `(value as int) as string` explicitly.
- JSON value keys are LOWERCASE on disk and must stay so: PapyrusUtil's JsonUtil runs `boost::to_lower` on every key it reads or writes (`ExternalFile::GetValue` / `SetValue` in External.cpp) but parses the file verbatim, and jsoncpp member lookup is case-sensitive, so a hand-authored `"NippleSize"` key is never found (the 1.1.2 bug: presets and Import silently skipped the nipple sliders). The `morphs` string LIST holds values, not keys, so it keeps the exact SKEE slider names from `ABM_Quest.FullMorphSet()` (mixed case); keep the two in sync - the lowercase of every list entry is a value key. Same rule for the body-patch files under `patches\`.
- JsonUtil API quick-reference: `StringListClear/Count/Get/Add(file, listKey, ...)`, `GetStringValue(file, key, missing)` (third arg positional), `SetStringValue(file, key, value)`.
- Papyrus does not support named arguments in the stock CK compiler. Always use positional args.

## Commit Conventions

- **Never include a `Co-Authored-By: Claude ...` trailer** in commit messages. Commits should look authored solely by the human user.
- One-line summaries, imperative mood; body only when the *why* would be lost.
