ScriptName ABM_Native Hidden
{Bindings for the OPTIONAL ArousedBodyMorphs.dll.

 With the DLL installed and a backend detected, it takes over the whole update
 pipeline -- per-actor refreshes, the player poll, armor changes and the SKEE
 writes -- off the Papyrus VM. Papyrus keeps the MCM and settings, mirroring
 them here via PushConfig/PushMorphTable.

 Without the DLL every native here is unbound: ALWAYS gate on IsInstalled(),
 which needs only SKSE. ABM_PlayerAlias.NativeActive() is the combined gate.}

Bool Function IsInstalled() Global
	{True when the DLL is registered with SKSE. Safe to call unconditionally;
	 the natives below are only callable when it is true.}
	Return SKSE.GetPluginVersion("ArousedBodyMorphs") > 0
EndFunction

Bool Function IsActive() Global Native
{True when a native arousal backend was detected AND SKEE's BodyMorph
 interface was acquired -- i.e. the DLL owns the update pipeline.}

String Function GetBackendName() Global Native
{Human-readable backend line for the MCM requirements row.}

Int Function UpdateActor(Actor akActor) Global Native
{Native mirror of ABM_PlayerAlias.UpdateActor. Returns the arousal in effect,
 -2 skipped by filters/disabled, -1 unavailable. Filters and the arousal read
 run inline so the return code is real; the SKEE write is queued to the main
 thread and lands within a frame -- doing it on the VM thread would race the
 renderer.}

Function ClearActorMorphs(Actor akActor) Global Native
{Drop every morph under our NIO key; queued to the main thread.}

Function PushConfig(Bool modEnabled, Bool ignoreMales, Bool ignoreDead, Bool ignoreMaleBeast, Bool ignoreFemaleBeast, Bool suppressUnderArmor, Float underArmorScale, Float pollInterval, Float scanRadius, Bool debugMode) Global Native
{Mirror the MCM option block into the DLL. Call after any change.}

Function PushMorphTable(String[] names, Float[] maxValues) Global Native
{Mirror the morph table (128-slot arrays, trailing empties ignored).}
