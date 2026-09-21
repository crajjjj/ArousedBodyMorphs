# Aroused BodyMorphs

Skyrim SE/AE mod that drives BodyMorph sliders on nipples, areolas and vagina in
proportion to an actor's [SexLab Aroused] arousal value — 0 arousal = no morph,
100 = the full per-morph value set in the MCM, linear in between. Works on the
player and nearby NPCs.

Standalone mod: ESL-flagged plugin, `ABM_*` Papyrus scripts, area-grouped MCM.

## Features

- 23 default morphs targeting **CBBE 3BA** slider names, grouped in the MCM by
  area: Nipples / Areolas / Vagina / Other
- Intensity presets (Minimal / Natural / Noticeable / Exaggerated)
- Master on/off switch that fully clears the mod's morphs when disabled
- Player poll for mid-scene responsiveness (SLA only broadcasts every ~120 s)
- Under-armor suppression with smooth reveal tween; any worn item with a
  cuirass / body-clothing keyword counts as a top, and Advanced Nudity Detection
  (Nude / Topless / Showing Breasts) overrides it back to bare for skimpy tops
  and for keyworded accessories
- Actor filters (males / dead / creatures)
- JSON import/export of settings and custom morph tables — imported morphs are
  auto-grouped by name
- Body-agnostic: any BodySlide-built body works via a custom morph table.
  Ready-made **UBE 2.0** and **BHUNP** patches live in [patches/](patches/) —
  install one as a separate mod after ABM and hit MCM → Import (sliders a body
  doesn't define are silent no-ops, so mixed-body load orders can merge tables)
- Debug lesser power that dumps an actor's morph state to the Papyrus log
- **Optional native SKSE layer** ([native/](native/)): event-driven updates via
  OSL Aroused's per-actor arousal events or SLA NG's C API, with all morph
  writes batched through SKEE's native interface — the Papyrus pipeline stays
  as the fallback for legacy SLA forks or DLL-less installs

## Requirements

SKSE64, SkyUI, RaceMenu (SKEE/NiOverride), PapyrusUtil, and any SexLab Aroused
flavor (NG recommended; OSL Aroused's stub and legacy forks work too). SexLab
itself is NOT required — OStim-only setups work. A BodySlide-built body with
morph data is required for the effect to be visible.

## Repository layout

```
dist/                 The installable mod (MO2-ready): ESP, scripts, JSON presets
  ArousedBodyMorphs.esp
  source/scripts/     Papyrus sources (ABM_Quest, ABM_PlayerAlias,
                      ABM_ConfigMenu, ABM_DebugSpellEffect)
  scripts/            Compiled .pex output
  SKSE/...            Intensity presets + sample morph.json
patches/              Data-only body patches, each zipped separately (morph
                      table + presets renamed to that body's sliders; no
                      plugin, no scripts): UBE/ (UBE 2.0), BHUNP/
skyrimse.ppj          Papyrus project: compiles dist/source → dist/scripts and
                      zips dist/ into Release/ArousedBodyMorphs.zip
native/               Optional SKSE DLL (xmake + CommonLibSSE-NG submodule);
                      builds ArousedBodyMorphs.dll into dist/SKSE/Plugins
```

Build with [Pyro] or any PapyrusCompiler front end using `skyrimse.ppj` (import
paths in the PPJ point at local dependency checkouts — adjust for your setup).

## Credits

Inspired by the ArousedNips family of mods and their community forks.

## License

Copyright (C) 2025-2026 crajjjj. Aroused BodyMorphs is free software under the
[GNU General Public License v3.0](LICENSE) or (at your option) any later
version, and comes with **no warranty**.

The SKSE plugin is built on
[CommonLibSSE-NG](https://github.com/alandtse/CommonLibSSE-NG), which is
GPL-3.0, so the mod is distributed under the same terms. The complete
corresponding source is this repository; the Papyrus sources and a copy of the
license also ship inside the download (`source\scripts` and `LICENSE.txt`).

[SexLab Aroused]: https://github.com/crajjjj/SexlabArousedNG
[Pyro]: https://github.com/fireundubh/pyro
