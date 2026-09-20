Aroused BodyMorphs 1.1.0
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
- SexLab Aroused -- any flavor: SexLab Aroused NG, published on Nexus as
  SLO Aroused NG (recommended), OSL Aroused (its SLA stub),
  SLAX / SSELoose / eXtended (legacy)
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
  covered, with a smooth ~1s reveal when the top comes off. Any worn item with
  a cuirass / body-clothing keyword counts, so bras and bikini tops that sit on
  an auxiliary slot instead of the body slot are caught too. With Advanced
  Nudity Detection installed a top still reads as bare while AND reports Nude,
  Topless or Showing Breasts -- that covers skimpy and open-front tops, and
  also corsets and piercings that only inherited the keyword.
  Which sliders it scales is listed in suppress.json: the nipple and areola
  sliders of all three supported bodies, by name, and nothing else -- since
  "covered" is a chest test it says nothing about the rest, and a skimpy
  armor can leave those on show. Add or remove names to taste; an entry can
  also be a whole area (nipples / areolas / vagina / other), which is the
  one-liner for a body whose sliders aren't listed. Read on every game load
  and on Import Settings
- Actor filters: ignore males / dead / male beasts / female beasts;
  NPC scan radius (0 = player only)
- Translated MCM in 11 languages: English, Chinese, Czech, French, German,
  Italian, Japanese, Polish, Russian, Spanish, Ukrainian. The game's language
  picks the file automatically.
- Import/Export of all settings + the morph table via JSON
  (SKSE\Plugins\StorageUtilData\ArousedBodyMorphs\config.json + morph.json;
  suppress.json lives there too and is edited by hand, not by the MCM)
- Debug mode with a lesser power that dumps an actor's morph state to the
  Papyrus log
- Optional native SKSE layer (ArousedBodyMorphs.dll): with SexLab Aroused NG
  or OSL Aroused installed, updates become event-driven / natively polled and
  all morph writes go through SKEE directly -- much lower script load. Without
  the DLL (or on legacy SLA forks) the Papyrus pipeline runs as before. The
  MCM Requirements section shows which mode is active.
  Known difference in native mode: armor removal snaps to the bare state
  instantly -- the ~1s reveal ease is Papyrus-mode only for now.


Translations
-----------
Interface\Translations\ArousedBodyMorphs_<LANGUAGE>.txt, one file per language.
The non-English files are machine-assisted translations that have not been
reviewed by native speakers -- corrections are very welcome, and fixing one is
just editing one file, no scripts involved.

If you edit or add one, two rules matter:
- Save as UTF-16 LE WITH BOM, tab between the $key and the text. Saving as
  UTF-8 is the usual reason a translation silently does not load.
- SkyUI only substitutes when the WHOLE string matches a key, and some names
  must stay exactly as they are: SexLab Aroused, RaceMenu, NiOverride, SKEE,
  SKSE, BodySlide, MCM, Papyrus, config.json, morph.json, the preset names
  (Minimal / Natural / Noticeable / Exaggerated -- these are also filenames),
  and NippleSize, which is a slider label shown elsewhere in the menu.


Credits
-------
Inspired by the ArousedNips family of mods and their community forks.
