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
- Under-armor suppression with smooth reveal tween; Advanced Nudity Detection
  aware
- Actor filters (males / dead / creatures), SexLab per-stage morph bump
- JSON import/export of settings and custom morph tables — imported morphs are
  auto-grouped by name
- Debug lesser power that dumps an actor's morph state to the Papyrus log
- **Optional native SKSE layer** ([native/](native/)): event-driven updates via
  OSL Aroused's per-actor arousal events or SLA NG's C API, with all morph
  writes batched through SKEE's native interface — the Papyrus pipeline stays
  as the fallback for legacy SLA forks or DLL-less installs

## Requirements

SKSE64, SkyUI, RaceMenu (SKEE/NiOverride), PapyrusUtil, SexLab Framework, and
any SexLab Aroused flavor (NG recommended; OSL Aroused's stub and legacy forks
work too). A BodySlide-built body with morph data is required for the effect to
be visible.

## Repository layout

```
dist/                 The installable mod (MO2-ready): ESP, scripts, JSON presets
  ArousedBodyMorphs.esp
  source/scripts/     Papyrus sources (ABM_Quest, ABM_PlayerAlias,
                      ABM_ConfigMenu, ABM_DebugSpellEffect)
  scripts/            Compiled .pex output
  SKSE/...            Intensity presets + sample morph.json
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

GPL-3.0 — see [LICENSE](LICENSE).

[SexLab Aroused]: https://github.com/crajjjj/SexlabArousedNG
[Pyro]: https://github.com/fireundubh/pyro
