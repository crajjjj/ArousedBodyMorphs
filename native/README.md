# ArousedBodyMorphs native layer (optional SKSE DLL)

Event-driven replacement for the Papyrus update pipeline. When the DLL is
installed and a native arousal backend is present, it owns detection, events,
polling, actor filters, under-armor suppression and the SKEE BodyMorph writes;
the Papyrus side keeps only the MCM and persisted settings (mirrored in via
`ABM_Native.PushConfig` / `PushMorphTable`). Without the DLL — or on a legacy
Papyrus-only SLA fork — the Papyrus pipeline runs unchanged, so the DLL is
strictly optional.

## Backends

| Framework | Detection | Read | Updates |
|---|---|---|---|
| SexLab Aroused NG / SLO NG | `SexlabArousedNG.dll` | `SLA_GetArousalInt` (C API, GetProcAddress) | native player poll (MCM interval) + `sla_UpdateComplete` heartbeat sweep of nearby NPCs |
| OSL Aroused | `OSLAroused.dll` | `GetArousalExt` | fully event-driven via `OSLA_ActorArousalUpdated` per-actor mod events — no polling |
| legacy SLA forks | none | — | DLL idles; Papyrus pipeline as before |

Morphs are written through RaceMenu's `IBodyMorphInterface` (acquired via the
`skee` messaging handshake) under the NIO key `ArousedBodyMorphs.esp` — same
key as the Papyrus path, so mixed sessions stay consistent and the MCM master
switch clears everything either way.

## Building

CommonLibSSE-NG (alandtse fork) is vendored as a git submodule, pinned to
v8.0.1 (latest at scaffold time; bump by checking out a newer `ng` commit in
the submodule).

```
git submodule update --init native/lib/commonlibsse-ng
cd native
xmake f -m release    # first run compiles CommonLibSSE-NG
xmake                 # builds + deploys the DLL to ../dist/SKSE/Plugins
```

Requires MSVC (VS 2022+) and xmake 3.0+. Set `COMMONLIB_PREBUILT=1` to fetch
NG's prebuilt bundle instead of compiling it.

## Known gaps vs the Papyrus path

- The ~1s reveal ease when body armor comes off is not reproduced natively yet
  (armor changes snap). See the TODO in `src/Events.cpp`.
- The SexLab `StageStart` +50 bump still originates in Papyrus
  (`SexLabFramework.HookActors` is a Papyrus API); in native mode the actors it
  resolves are routed through `ABM_Native.UpdateActor`, so only the actor
  resolution costs VM time.
