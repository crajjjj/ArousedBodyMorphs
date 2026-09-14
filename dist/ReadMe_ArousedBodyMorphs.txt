Aroused BodyMorphs 1.0.4
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
- Actor filters: ignore males / dead / male beasts / female beasts;
  NPC scan radius (0 = player only)
- Translatable MCM: Interface\Translations\ArousedBodyMorphs_<LANGUAGE>.txt
  (English shipped for all 10 languages; drop in a translated file to replace)
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
