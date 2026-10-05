ScriptName ABM_Native Hidden
{Bindings for the OPTIONAL ArousedBodyMorphs.dll.

 With the DLL installed and a backend detected, it takes over the whole update
 pipeline -- per-actor refreshes, the player poll, armor changes and the SKEE
 writes -- off the Papyrus VM. Papyrus keeps the MCM and settings, mirroring
 them here via PushConfig / PushMorphTable / PushSuppressFlags /
 PushMorphScopes.

 Without the DLL every native here is unbound: ALWAYS gate on IsInstalled(),
 which needs only SKSE. ABM_PlayerAlias.NativeActive() is the combined gate.}

Bool Function IsInstalled() Global
	{True when the DLL is registered with SKSE. Safe to call unconditionally;
	 the natives below are only callable when it is true.}
	Return SKSE.GetPluginVersion("ArousedBodyMorphs") > 0
EndFunction

Bool Function SupportsScopes() Global
	{True when the installed DLL is 1.2.0 or newer, i.e. it exports
	 PushMorphScopes and filters slots per actor. An older DLL writes every slot
	 it is given to every actor, so it must be handed the main table alone --
	 see ABM_PlayerAlias.PushConfigToNative. The version is the DLL's own,
	 packed major<<24 | minor<<16 | patch<<4 (REL::Version::pack).}
	Return SKSE.GetPluginVersion("ArousedBodyMorphs") >= 0x01020000
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

Function PushSuppressFlags(Int[] suppressed) Global Native
{Mark which slots of the pushed table the under-armor scale applies to: 1 =
 suppressed, parallel to PushMorphTable's arrays. ABM_Quest resolves
 suppress.json, so the DLL never reads it. Int, not Bool, so the Papyrus array
 maps to a plain std::vector on the native side.

 Deliberately a SEPARATE native rather than a third PushMorphTable argument:
 this is the only call a pre-1.1.0 DLL doesn't export, and PushConfigToNative
 makes it last, so a scripts-only update degrades to that DLL's old behaviour
 (scale everything while covered) instead of leaving it with no morph table at
 all -- i.e. a silently dead mod.}

Function PushMorphScopes(Int[] bodies, Int[] playerOnly) Global Native
{Say which actors each slot of the pushed table is for, parallel to
 PushMorphTable's arrays: bodies = ABM_Quest.MorphBody (0 main table, 1 UBE),
 playerOnly = ABM_Quest.MorphPlayerOnly (1 = the player alone). The DLL then
 writes a slot only to an actor of that body, and a player-only slot only to
 the player.

 Exported from 1.2.0 on: gate on SupportsScopes(), never call it blind.}
