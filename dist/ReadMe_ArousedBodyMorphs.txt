Aroused BodyMorphs 1.0.0
========================

by crajjjj -- https://github.com/crajjjj/ArousedBodyMorphs


What it does
------------
Drives BodyMorph sliders on nipples, areolas and vagina in proportion to an
actor's SexLab Aroused arousal value: 0 arousal = no morph, 100 = the full
per-morph value you set in the MCM, linear in between. Works on the player and
on nearby NPCs.

The default morph set targets CBBE 3BA slider names (23 sliders: nipple set,
areola, and the 3BA labia/vagina/clit set). The MCM groups the sliders by area
(Nipples / Areolas / Vagina / Other). Any custom morph list can be imported via
JSON; imported morphs sort themselves into the area groups by name.

A BodySlide-built body (and body-armor) WITH morph data ("Build Morphs" checked)
is required for anything to be visible in game.


Requirements
------------
- SKSE64, SkyUI
- RaceMenu (SKEE / NiOverride) -- the BodyMorph API
- PapyrusUtil
- SexLab Aroused -- any flavor: SexLab Aroused NG / SLO Aroused NG (recommended),
  OSL Aroused (its SLA stub), SLAX / SSELoose / eXtended (legacy)
- A 3BA-compatible body built in BodySlide with morphs (or import your own
  morph list for other bodies)
- Optional: Advanced Nudity Detection -- improves the "under armor" detection
  for skimpy/bikini tops


Features
--------
- Per-morph max-value sliders (0.01 step, -3..3), grouped by area in the MCM
- Intensity presets: Minimal / Natural / Noticeable / Exaggerated
  (install default is Natural)
- Master "Mod enabled" switch -- turning it off clears every morph this mod
  owns and puts it fully dormant
- Player poll (default 5s, configurable, 0 = off) for mid-scene responsiveness;
  NPCs update on SexLab Aroused's scan tick
- Under-armor suppression: morphs scale down (default: flat) while the chest is
  covered, with a smooth ~1s reveal when the top comes off; Advanced Nudity
  Detection aware
- Actor filters: ignore males / dead / male beasts / female beasts
- Import/Export of all settings + the morph table via JSON
  (SKSE\Plugins\StorageUtilData\ArousedBodyMorphs\config.json + morph.json)
- Debug mode with a lesser power that dumps an actor's morph state to the
  Papyrus log
- Optional native SKSE layer (ArousedBodyMorphs.dll): with SexLab Aroused NG
  or OSL Aroused installed, updates become event-driven / natively polled and
  all morph writes go through SKEE directly -- much lower script load. Without
  the DLL (or on legacy SLA forks) the Papyrus pipeline runs as before. The
  MCM Requirements section shows which mode is active.
  Known difference in native mode: armor removal snaps to the bare state
  instantly -- the ~1s reveal ease is Papyrus-mode only for now.


Credits
-------
Inspired by the ArousedNips family of mods and their community forks.


Changelog
---------
1.0.0
- Initial release:
  - ESL-flagged plugin ArousedBodyMorphs.esp, ABM_* script set,
    NIO BodyMorph key "ArousedBodyMorphs.esp",
    JSON under SKSE\Plugins\StorageUtilData\ArousedBodyMorphs\.
  - MCM Morphs page groups sliders by area: Nipples / Areolas / Vagina / Other.
    Imported custom morphs are grouped by name automatically.
  - Intensity preset files use the exact morph names as keys.
  - Master switch, player poll, under-armor suppression + reveal tween,
    Advanced Nudity Detection top-nudity gating, actor filters, intensity
    presets, import/export, debug spell, multi-fork SLA detection.
  - Optional native SKSE layer: event-driven updates on OSL Aroused
    (OSLA_ActorArousalUpdated), native poll + heartbeat sweep on SLA NG
    (C API), SKEE-direct morph writes; Papyrus fallback for legacy forks.
  - No SexLab requirement: masters are Skyrim, Update and SexLabAroused only,
    so OStim-only setups load fine.
  - Correctness/performance pass:
    - Beast filters actually work now: creature detection reads the race's
      ActorTypeNPC keyword (ActorBase.GetSex() never returns the 2/3 creature
      codes the old check tested for -- female creatures slipped through).
      Papyrus and native mode now use the identical test.
    - Unchanged-value skip in both pipelines: an update that would write the
      values the body already has now costs a single read instead of 23 morph
      writes plus a model-weight rebuild. The steady-state player poll no
      longer rebuilds the body mesh every tick, and the NPC heartbeat sweep
      no longer touches never-aroused bystanders at all.
    - Native DLL: morph/clear writes requested from Papyrus (debug spell, MCM
      "Check now", master switch) are queued to the game's main thread instead
      of running on the script VM thread -- fixes a potential crash when the
      renderer read the body mesh mid-write. Form lookups resolve once at
      startup, an outfit swap coalesces into a single refresh, and the poll
      thread shuts down cleanly on game exit instead of stalling it.
    - Papyrus: reveal tween is 5 steps instead of 10 (half the mesh rebuilds,
      same look), redress equip-event bursts are debounced, and the native-DLL
      presence check is cached per load instead of re-asked per actor.
