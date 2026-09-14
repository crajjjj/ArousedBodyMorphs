ScriptName ABM_Native Hidden
{Bindings for the OPTIONAL ArousedBodyMorphs.dll native layer.

 When the DLL is installed and a native arousal backend is detected (SexLab
 Aroused NG's C API, or OSL Aroused's exports + OSLA_ActorArousalUpdated
 events), the DLL takes over the whole update pipeline: event-driven per-actor
 refreshes, the player poll, armor-change refreshes, and the SKEE morph writes
 -- all off the Papyrus VM. The Papyrus side keeps the MCM and persisted
 settings, mirroring them here via PushConfig/PushMorphTable.

 Without the DLL (or on a legacy Papyrus-only SLA fork) every native function
 here is unbound -- ALWAYS gate calls with IsInstalled(), which needs only
 SKSE. ABM_PlayerAlias.NativeActive() is the canonical combined gate.}

Bool Function IsInstalled() Global
	{True when ArousedBodyMorphs.dll is loaded (registered with SKSE). Safe to
	 call unconditionally; the natives below are only callable when this is true.}
	Return SKSE.GetPluginVersion("ArousedBodyMorphs") > 0
EndFunction

Bool Function IsActive() Global Native
{True when a native arousal backend was detected AND SKEE's BodyMorph
 interface was acquired -- i.e. the DLL owns the update pipeline.}

String Function GetBackendName() Global Native
{Human-readable backend line for the MCM requirements row.}

Int Function UpdateActor(Actor akActor) Global Native
{Native mirror of ABM_PlayerAlias.UpdateActor: fresh arousal read, filters,
 under-armor scale, SKEE morph writes. Returns the arousal written, -2 if
 skipped by filters/disabled, -1 if unavailable.}

Function ClearActorMorphs(Actor akActor) Global Native
{Drop every morph under the ArousedBodyMorphs.esp NIO key for this actor.}

Function PushConfig(Bool modEnabled, Bool ignoreMales, Bool ignoreDead, Bool ignoreMaleBeast, Bool ignoreFemaleBeast, Bool suppressUnderArmor, Float underArmorScale, Float pollInterval, Float scanRadius, Bool debugMode) Global Native
{Mirror the MCM option block into the DLL. Call after any change.}

Function PushMorphTable(String[] names, Float[] maxValues) Global Native
{Mirror the morph table (128-slot arrays, trailing empties ignored).}
