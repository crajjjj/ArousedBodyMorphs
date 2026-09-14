ScriptName ABM_PlayerAlias extends ReferenceAlias
{Player alias: requirements detection, event handling, and the morph writer.}

ABM_Quest Property MainQuest Auto

; RaceMenu / SKEE version gates for the BodyMorph API
Int Property SKEE_VERSION = 1 AutoReadOnly
Int Property NIOVERRIDE_SCRIPT_VERSION = 6 AutoReadOnly

; NIO key for every morph we write, so we can clear exactly ours.
String Property NIO_KEY = "ArousedBodyMorphs.esp" AutoReadOnly hidden

slaFrameworkScr Property sla_Framework Auto

; Top-nudity state, resolved per load by ResolveNudityDetection(). See IsTopCovered.
Bool AND_Resolved = false
Faction AND_Nude
Faction AND_Topless
Keyword kwArmorCuirass
Keyword kwClothingBody

; Reveal-tween state: last-applied scale (the tween's start point), and a
; generation any direct player update bumps so an in-flight tween bails.
Float PlayerArmorScale = 1.0
Int tweenGen = 0

; Last arousal applied to the player; PokePlayerArousal reports it so the MCM
; row can't disagree with the body.
Int PlayerLastArousal = 0

; Debounce generation for RefreshOnArmorChange: a redress fires one equip event
; per item, so superseded handlers bail instead of each doing a refresh.
Int armorGen = 0

; NativeActive() cached per load -- both inputs need a game restart to change,
; and it is asked once per actor per sweep.
Bool nativeMode = false

; Creature test for the beast filters: a race WITHOUT ActorTypeNPC is a
; creature. GetSex() is only -1/0/1 and does not encode creature-ness.
Keyword kwActorTypeNPC

; Cached player. Game.GetPlayer() is a native call and UpdateActor made one per
; actor per sweep for the is-this-the-player test; this IS the player alias, so
; its own reference answers it. Never changes within a save; re-resolved per load.
Actor PlayerRef

Actor Function GetPlayerRef()
	{The player, resolved once from the alias's own reference; falls back to
	 Game.GetPlayer() if the alias isn't filled yet, so no caller gets None.}
	If PlayerRef
		Return PlayerRef
	EndIf
	PlayerRef = GetActorReference()
	If !PlayerRef
		PlayerRef = Game.GetPlayer()
	EndIf
	Return PlayerRef
EndFunction

Function RefreshPlayer()
	{Re-apply the player's morphs now. MCM entry point (OnConfigClose).}
	UpdateActor(GetPlayerRef(), false)
EndFunction

Event OnInit()
	{Warm the sla_Framework cache on first fill; called for the side effect.}
	GetFramework()
EndEvent

Bool Function NativeActive()
	{True when the optional DLL is installed AND found a backend + SKEE. It then
	 owns the whole pipeline and every Papyrus path here stands down. Cached per
	 load by ResolveNativeMode.}
	Return nativeMode
EndFunction

Function ResolveNativeMode()
	{The probe behind NativeActive(). && short-circuits, so IsActive (unbound
	 without the DLL) is never reached when the DLL is absent.}
	nativeMode = ABM_Native.IsInstalled() && ABM_Native.IsActive()
EndFunction

Function PushConfigToNative()
	{Mirror options + morph table into the DLL. The MCM stays the source of
	 truth; called on load, SetModEnabled, RestartPolling and MCM close.}
	If !ABM_Native.IsInstalled()
		return
	EndIf
	ABM_Native.PushConfig(MainQuest.ModEnabled, MainQuest.IgnoreMales, MainQuest.IgnoreDead, MainQuest.IgnoreMaleBeast, MainQuest.IgnoreFemaleBeast, MainQuest.SuppressUnderArmor, MainQuest.UnderArmorScale, MainQuest.PollInterval, MainQuest.ScanCellRadius, MainQuest.DebugMode)
	ABM_Native.PushMorphTable(MainQuest.MorphNames, MainQuest.MaxValue)
EndFunction

slaFrameworkScr Function GetFramework()
	{Defensive accessor for the SLA framework. Cheap once cached; falls back to
	 Quest.GetQuest("sla_Framework") -- every fork ships that editor ID -- and
	 caches the result. The fallback exists because the predecessor ESP was seen
	 in the wild with this Auto property silently unwired.}
	If sla_Framework
		Return sla_Framework
	EndIf
	sla_Framework = Quest.GetQuest("sla_Framework") as slaFrameworkScr
	If sla_Framework
		debug.Trace("ABM: populated sla_Framework Auto property via Quest.GetQuest fallback")
	EndIf
	Return sla_Framework
EndFunction

Event OnPlayerLoadGame()
	{Re-check requirements on every game load, and re-resolve the cached
	 framework / native-mode / player lookups for this save.}
	GetFramework()

	; Before the abort paths below, so the armor handlers see the right mode
	; even when requirements fail.
	ResolveNativeMode()

	PlayerRef = None
	GetPlayerRef()

	if MainQuest.DebugMode
		debug.Notification("Aroused BodyMorphs: checking for requirements")
		debug.Trace("ABM: checking for requirements")
	EndIf

	;Check Requirements
	if !CheckNiOverride()
		;NiO check fail
		MainQuest.isNioOk = false
		debug.Notification("Aroused BodyMorphs: NiOverride Version check failed, aborting.")
		debug.Trace("ABM: NiOverride Version check failed, aborting.")
		return
	Else
		MainQuest.isNioOk = true
	EndIf

	; Multi-fork detection via GetVersion(), which every fork implements.
	; Date-stamped: OSL stub 20140124, SLAXSE2022 20190720, real NG >= 20200000
	; (SLA NG's own gate). We only use the read path, portable across all of them.
	slaFrameworkScr framework = GetFramework()
	if !framework
		; Property and fallback both None -- SexLabAroused.esm isn't loaded.
		MainQuest.isSLAroused28 = false
		MainQuest.isSLAroused29 = false
		debug.Notification("Aroused BodyMorphs: SLA framework not found (Auto property unwired AND Quest.GetQuest fallback failed), aborting")
		debug.Trace("ABM: SLA framework not found (Auto property unwired AND Quest.GetQuest fallback failed), aborting")
		return
	endif
	int slaVersion = framework.GetVersion()

	if slaVersion >= 20200000
		MainQuest.isSLAroused28 = false
		MainQuest.isSLAroused29 = true
	elseif slaVersion > 0
		; Any pre-NG fork; GetActorArousal still works.
		MainQuest.isSLAroused28 = true
		MainQuest.isSLAroused29 = false
	else
		MainQuest.isSLAroused28 = false
		MainQuest.isSLAroused29 = false
		debug.Notification("Aroused BodyMorphs: SexLab Aroused framework not detected (GetVersion returned " + slaVersion + "), aborting")
		debug.Trace("ABM: SexLab Aroused framework not detected (GetVersion returned " + slaVersion + "), aborting")
		return
	endif

	;success
	MainQuest.ResetDefaults()

	; Re-run per load so an AND install/uninstall since the last save is seen.
	ResolveNudityDetection()

	RegisterForModevent("sla_UpdateComplete", "OnArousalComputed")

	PushConfigToNative()

	; Player poll. SLA only broadcasts every ~120s, so this keeps the player
	; responsive mid-scene without lowering SLA's global scan rate. Skipped for
	; a dormant mod, and in native mode (the DLL runs its own poll).
	Float pollInterval = MainQuest.PollInterval
	If pollInterval > 0.0 && MainQuest.ModEnabled && !NativeActive()
		RegisterForSingleUpdate(pollInterval)
	EndIf

	IF MainQuest.DebugMode
		debug.Notification("Aroused BodyMorphs: requirements check successful")
		debug.Trace("ABM: requirements check successful")
	EndIf
EndEvent

Event OnUpdate()
	{Player-only refresh between SLA heartbeats. Not used in native mode.}
	If !IsActive()
		; Off, or requirements lost mid-save -- stop. Re-armed by RestartPolling,
		; SetModEnabled, or the next load.
		return
	EndIf
	If NativeActive()
		; The DLL polls itself -- let this loop die.
		return
	EndIf

	UpdateActor(GetPlayerRef(), false)

	Float pollInterval = MainQuest.PollInterval
	If pollInterval > 0.0
		RegisterForSingleUpdate(pollInterval)
	EndIf
EndEvent

Function RestartPolling()
	{MCM entry point for a PollInterval change: re-arm at the new interval now,
	 including restarting a loop that was stopped at 0. Native mode needs only
	 the push.}
	UnregisterForUpdate()
	PushConfigToNative()
	If NativeActive()
		return
	EndIf
	Float pollInterval = MainQuest.PollInterval
	If pollInterval > 0.0 && IsActive()
		RegisterForSingleUpdate(pollInterval)
	EndIf
EndFunction

Bool Function IsActive()
	{Single gate for every path that writes morphs: switched on AND requirements
	 met. Three property reads, fine to call per tick.}
	Return MainQuest.ModEnabled && MainQuest.isNioOk && (MainQuest.isSLAroused28 || MainQuest.isSLAroused29)
EndFunction

Function SetModEnabled(Bool enabled)
	{Master on/off toggle. Owns the whole transition so it takes effect now, not
	 on the next heartbeat: on re-applies, off clears every morph we wrote (frozen
	 morphs would make "disabled" look like "stuck"). Both cover player AND nearby
	 NPCs. tweenGen is bumped first so an in-flight tween can't repaint after the
	 clear.}
	tweenGen += 1
	MainQuest.ModEnabled = enabled
	; Native DLL first: its poll thread and event sinks gate on the pushed
	; ModEnabled, so the switch reaches them before we re-apply or clear.
	PushConfigToNative()
	If enabled
		Bool doDebug = MainQuest.DebugMode
		UpdateActor(GetPlayerRef(), doDebug)
		UpdateNearbyActors(doDebug)
		RestartPolling()
	Else
		UnregisterForUpdate()
		ClearAllMorphs()
	EndIf
EndFunction

Actor[] Function ScanNearbyAroused(Bool ignoreDead)
	{The aroused NPCs near the player, or None when SLA can't be queried. Shared
	 by the heartbeat and both master-switch directions so all three agree on who
	 counts as nearby. Bails on a None slaArousal faction rather than feeding it
	 to ScanCellNPCsByFaction, where it is unspecified.}
	slaFrameworkScr framework = GetFramework()
	If !framework
		Return None
	EndIf
	If !framework.slaArousal
		If MainQuest.DebugMode
			debug.Trace("ABM: framework.slaArousal is None; skipping NPC scan")
		EndIf
		Return None
	EndIf
	Return MiscUtil.ScanCellNPCsByFaction(framework.slaArousal, GetPlayerRef(), MainQuest.ScanCellRadius, 0, 127, ignoreDead)
EndFunction

Function UpdateNearbyActors(Bool doDebug)
	{Push morphs to nearby aroused NPCs, so they return with the player.}
	Actor[] theActors = ScanNearbyAroused(MainQuest.IgnoreDead)
	If !theActors
		return
	EndIf
	int i = 0
	int len = theActors.length
	While i < len
		; Scan results can have null slots if SLA's faction-rank cache is mid-update.
		If theActors[i]
			UpdateActor(theActors[i], doDebug)
		EndIf
		i += 1
	EndWhile
EndFunction

Function ClearActorMorphs(Actor who)
	{Drop every morph under our NIO key. Only our key, so other mods' morphs and
	 the user's RaceMenu sliders survive. Native mode routes through the DLL to
	 keep the whole write path on the main thread.}
	If !who
		return
	EndIf
	If NativeActive()
		ABM_Native.ClearActorMorphs(who)
		return
	EndIf
	NiOverride.ClearBodyMorphKeys(who, NIO_KEY)
	NiOverride.UpdateModelWeight(who)
EndFunction

Function ClearAllMorphs()
	{Clear our morphs from the player and nearby aroused NPCs (mod switched off).

	 The isNioOk bail matters: the master toggle is never greyed out, so it can be
	 clicked with no SKEE installed, where these natives have nothing to bind to.
	 IgnoreDead is false here -- a corpse morphed while alive still needs cleaning.
	 NPCs beyond ScanCellRadius keep their values until back in range.}
	PlayerArmorScale = 1.0
	PlayerLastArousal = 0
	If !MainQuest.isNioOk
		return
	EndIf
	ClearActorMorphs(GetPlayerRef())

	Actor[] theActors = ScanNearbyAroused(false)
	If !theActors
		return
	EndIf
	int i = 0
	int len = theActors.length
	While i < len
		If theActors[i]
			ClearActorMorphs(theActors[i])
		EndIf
		i += 1
	EndWhile
EndFunction

Int Function PokePlayerArousal()
	{MCM "Player arousal" row: re-apply now and report what was applied (0..100),
	 or a sentinel the MCM labels itself -- -1 no framework, -2 excluded by the
	 actor filters (a number there would be a false pass), -3 mod switched off.
	 Reports what UpdateActor applied, not a second read, so it can't disagree
	 with the body.}
	If !MainQuest.ModEnabled
		Return -3
	EndIf
	If !GetFramework()
		Return -1
	EndIf
	If !UpdateActor(GetPlayerRef(), MainQuest.DebugMode)
		Return -2
	EndIf
	Return PlayerLastArousal
EndFunction

Bool Function CheckNiOverride()
	Return SKSE.GetPluginVersion("skee") >= SKEE_VERSION && NiOverride.GetScriptVersion() >= NIOVERRIDE_SCRIPT_VERSION
EndFunction

Function ResolveNudityDetection()
	{Resolve the AND factions, the vanilla body keywords and ActorTypeNPC, per
	 load. The AND formIDs (0x831 Nude, 0x832 Topless) match what SLA NG itself
	 resolves -- AND owns them, so any SLA fork works.}
	AND_Resolved = false
	AND_Nude = None
	AND_Topless = None
	If Game.GetModByName("Advanced Nudity Detection.esp") != 255
		AND_Nude    = Game.GetFormFromFile(0x831, "Advanced Nudity Detection.esp") as Faction
		AND_Topless = Game.GetFormFromFile(0x832, "Advanced Nudity Detection.esp") as Faction
		AND_Resolved = (AND_Nude != None) || (AND_Topless != None)
		If MainQuest.DebugMode
			debug.Trace("ABM: Advanced Nudity Detection found, top-nudity gating enabled")
		EndIf
	EndIf
	kwArmorCuirass = Keyword.GetKeyword("ArmorCuirass")
	kwClothingBody = Keyword.GetKeyword("ClothingBody")
	kwActorTypeNPC = Keyword.GetKeyword("ActorTypeNPC")
EndFunction

Bool Function IsTopCovered(Actor who)
	{True when the chest is covered, so the morphs scale down and don't clip.

	 Mirrors slamainscr.IsActorNaked: the worn-keyword check is primary and AND
	 only OVERRIDES covered -> bare. AND is deliberately not the sole authority --
	 its NPC factions come from a periodic player-cast scan, so an unscanned or
	 just-stripped NPC has no Topless rank and would wrongly read covered. Naked
	 bodies / SOS carry neither keyword, so they read bare.}
	If !(who.WornHasKeyword(kwArmorCuirass) || who.WornHasKeyword(kwClothingBody))
		Return false
	EndIf
	; A top is worn -- let AND override to bare for skimpy / bikini tops.
	If AND_Resolved
		If (AND_Nude && who.GetFactionRank(AND_Nude) == 1) || (AND_Topless && who.GetFactionRank(AND_Topless) == 1)
			Return false
		EndIf
	EndIf
	Return true
EndFunction

Event OnObjectEquipped(Form akBaseObject, ObjectReference akReference)
	{Snap (no ease) so the chest collapses before it can clip during a redress.}
	RefreshOnArmorChange(akBaseObject, false)
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akReference)
	{Player took something off -- if that bares the chest, ease the morphs back in.}
	RefreshOnArmorChange(akBaseObject, true)
EndEvent

Function RefreshOnArmorChange(Form akBaseObject, Bool wasRemoved)
	{Player-only refresh on equip/unequip. With AND a top change can come from any
	 slot, so we react to any armor after a short settle; without AND only the
	 body slot matters. Baring the chest eases in over ~1s, everything else snaps
	 -- notably equipping, so nipples flatten instantly.}
	If NativeActive()
		; The DLL's equip sink handles this.
		return
	EndIf
	If !MainQuest.SuppressUnderArmor
		return
	EndIf
	If !IsActive()
		return
	EndIf
	Armor armo = akBaseObject as Armor
	If !armo
		return
	EndIf
	If !AND_Resolved && !Math.LogicalAnd(armo.GetSlotMask(), 0x04)
		; Without AND, only body-slot (32) armor can change the covered state.
		return
	EndIf
	; Debounce: a redress fires one event per item and Utility.Wait unlocks the
	; script, so handlers overlap. Only the newest survives its wait -- and it
	; sees the final worn state anyway.
	armorGen += 1
	Int myGen = armorGen
	If AND_Resolved
		Utility.Wait(0.3)  ; let AND update its nudity factions first
		If myGen != armorGen
			return
		EndIf
	EndIf

	If wasRemoved && !IsTopCovered(GetPlayerRef())
		TweenPlayerReveal()
	Else
		UpdateActor(GetPlayerRef(), MainQuest.DebugMode)
	EndIf
EndFunction

Event OnArousalComputed(string eventName, string argString, float argNum, form sender)
	{SLA broadcast at the end of each scan tick: refresh player, then nearby NPCs.}
	If !MainQuest.ModEnabled
		; Registration is only remade on load, not on the toggle, so gate here.
		return
	EndIf
	If NativeActive()
		; The DLL sinks this itself -- doing it here would double the work.
		return
	EndIf
	bool doDebug = MainQuest.DebugMode
	If doDebug
		debug.Notification("Aroused BodyMorphs: Arousal event")
		debug.Trace("ABM: Arousal event")
	EndIf

	UpdateActor(GetPlayerRef(), doDebug)

	If argNum <= 0
		If doDebug
			debug.Notification("Aroused BodyMorphs: No aroused NPCs nearby, updating player only")
			debug.Trace("ABM: No aroused NPCs nearby, updating player only")
		EndIf
		return
	EndIf

	; None when SLA can't be queried -- skip the tick.
	Actor[] theActors = ScanNearbyAroused(MainQuest.IgnoreDead)
	If !theActors
		return
	EndIf
	; Slots can be null if SLA's faction-rank cache is mid-update.
	int i = 0
	int len = theActors.length
	While i < len
		If theActors[i]
			UpdateActor(theActors[i], doDebug)
		EndIf
		i += 1
	EndWhile

	If doDebug
		debug.Notification("Aroused BodyMorphs: Arousal event end")
		debug.Trace("ABM: Arousal event end")
	EndIf
endEvent

Bool Function UpdateActor(Actor who, bool doDebug=false)
	{Set morphs of "who" according to their arousal.

	 True when the morphs now reflect that arousal (written, or already at the
	 target and skipped); false on every bail-out. PokePlayerArousal uses the
	 return so the MCM row can't report a pass on a skipped actor.}
	If !who
		; The debug spell's crosshair fallback can pass None.
		return false
	EndIf
	If !MainQuest.ModEnabled
		; Belt and braces -- the debug spell reaches UpdateActor directly.
		return false
	EndIf
	If NativeActive()
		; One native call does filters, arousal read, scaling and all writes.
		Int applied = ABM_Native.UpdateActor(who)
		If who == GetPlayerRef()
			tweenGen += 1
			If applied >= 0
				PlayerLastArousal = applied
			EndIf
		EndIf
		return applied >= 0
	EndIf
	ActorBase whoBase = who.GetLeveledActorBase()
	If !whoBase
		; None for actors mid-spawn; can't filter by sex / IsDead without it.
		return false
	EndIf
	; GetSex() is -1 None / 0 Male / 1 Female and NOTHING else -- the 2/3
	; creature codes this once tested for don't exist, which made the beast
	; toggles dead code. Creature-ness comes from the race keyword instead,
	; matching the DLL. Sex -1 counts as male, as it does there.
	int sex = whoBase.GetSex()
	Bool isFemale = sex == 1
	Bool isCreature = false
	Race whoRace = who.GetRace()
	If whoRace && kwActorTypeNPC
		isCreature = !whoRace.HasKeyword(kwActorTypeNPC)
	EndIf
	String skipReason = ""
	If MainQuest.IgnoreMales && !isCreature && !isFemale
		skipReason = "is male"
	ElseIf MainQuest.IgnoreMaleBeast && isCreature && !isFemale
		skipReason = "is male beast"
	ElseIf MainQuest.IgnoreFemaleBeast && isCreature && isFemale
		skipReason = "is female beast"
	ElseIf MainQuest.IgnoreDead && who.IsDead()
		; The cell scan already filters these, but the poll and debug spell can
		; still arrive with a corpse.
		skipReason = "is dead"
	EndIf
	If skipReason != ""
		If doDebug
			debug.Notification("Aroused BodyMorphs: "+whoBase.GetName()+" "+skipReason+", skipping")
			debug.Trace("ABM: "+whoBase.GetName()+" "+skipReason+", skipping")
		EndIF
		return false
	EndIf

	; Portable across every fork. GetActorArousal forces a fresh recalculation
	; rather than returning the faction-rank cache SLA only refreshes on its
	; scan tick -- which is what makes the poll worth running.
	slaFrameworkScr framework = GetFramework()
	If !framework
		If doDebug
			debug.Notification("Aroused BodyMorphs: "+whoBase.GetName()+" -- SLA framework unavailable, skipping")
			debug.Trace("ABM: "+whoBase.GetName()+" -- SLA framework unavailable, skipping")
		EndIf
		return false
	EndIf
	int Arousal = framework.GetActorArousal(who)
	If Arousal > 100
		Arousal = 100
	ElseIf Arousal < 0
		Arousal = 0
	EndIf

	; Under-armor suppression: scale everything by UnderArmorScale while covered
	; (0.0 = flat, 1.0 = full) so fitted nipples don't poke through tops.
	Float armorScale = 1.0
	If MainQuest.SuppressUnderArmor && IsTopCovered(who)
		armorScale = MainQuest.UnderArmorScale
		If doDebug
			debug.Notification("Aroused BodyMorphs: "+whoBase.GetName()+" chest covered, scaling morphs x"+armorScale)
			debug.Trace("ABM: "+whoBase.GetName()+" chest covered, scaling morphs x"+armorScale)
		EndIf
	EndIf

	Bool isPlayer = who == GetPlayerRef()
	SetActorMorphs(who, Arousal, armorScale, doDebug)

	; Track the tween's start point + the reported arousal, and cancel any
	; in-flight tween -- a direct update supersedes it.
	If isPlayer
		PlayerArmorScale = armorScale
		PlayerLastArousal = Arousal
		tweenGen += 1
	EndIf
	return true
EndFunction

Function SetActorMorphs(Actor who, Int arousal, Float scale, Bool doDebug=false)
	{Write every morph = maxValue * arousal/100 * scale, then push the model
	 update. Shared by UpdateActor (a snap) and TweenPlayerReveal (one ease step).

	 Unchanged-value skip: UpdateModelWeight is by far the most expensive call
	 here, and arousal rarely moves between ticks. Every slot shares one factor,
	 so a single slot settles whether anything would change -- one GetBodyMorph
	 replaces 23 writes plus the rebuild. The probe reads back what WE wrote
	 (our key), making NiOverride the source of truth: nothing to invalidate on a
	 slider change, a save load, or an external clear, because the target moves
	 with the settings. DO NOT replace it with a remembered value.

	 The ModEnabled check lives here, the single point where morphs are written:
	 every external call unlocks the script, so the MCM can clear morphs mid-tween
	 and without this gate the rest of the step would repaint them.}
	If !MainQuest.ModEnabled
		return
	EndIf
	String[] morphNames = MainQuest.MorphNames
	Float[]  maxValues  = MainQuest.MaxValue

	; Integer division trap: arousal / 100 would truncate to 0 -- cast first.
	Float factor = (arousal as Float) / 100.0 * scale

	; Probe slot = first non-zero max; a zero-max slot reads 0 for every factor
	; and could never detect a change.
	Int p = 0
	While p < 128 && morphNames[p] != "" && maxValues[p] == 0.0
		p += 1
	EndWhile
	If p >= 128 || morphNames[p] == ""
		; Empty table, or every max is 0 -- nothing can ever be written.
		return
	EndIf
	; 1e-6: float32 noise here is ~1e-8, the smallest dialable step ~1e-4.
	If Math.Abs(NiOverride.GetBodyMorph(who, morphNames[p], NIO_KEY) - maxValues[p] * factor) < 0.000001
		return
	EndIf

	int j = 0
	while j < 128 && morphNames[j] != ""
		float Value = maxValues[j] * factor
		NiOverride.SetBodyMorph(who, morphNames[j], NIO_KEY, Value)
		If doDebug
			debug.Notification("Aroused BodyMorphs: setting "+morphNames[j]+" to "+Value)
			debug.Trace("ABM: setting "+morphNames[j]+" to "+Value)
		EndIf
		j += 1
	EndWhile
	NiOverride.UpdateModelWeight(who)
EndFunction

Function TweenPlayerReveal()
	{Ease the player's morphs from the applied scale up to the uncovered target
	 over ~1s. Arousal is read once and held. Bails if a newer update supersedes
	 it mid-ease.}
	If !IsActive()
		; Re-checked because the caller waited 0.3s for AND -- long enough for the
		; master switch to flip off, after which this would repaint what it cleared.
		return
	EndIf
	Actor player = GetPlayerRef()
	If !player
		return
	EndIf

	; Target scale after the armor change (1.0 = bare; still-covered -> no reveal).
	Float target = 1.0
	If MainQuest.SuppressUnderArmor && IsTopCovered(player)
		target = MainQuest.UnderArmorScale
	EndIf
	Float from = PlayerArmorScale
	If target == from
		; Already at the target (e.g. was never suppressed) -- nothing to animate.
		return
	EndIf

	slaFrameworkScr framework = GetFramework()
	If !framework
		return
	EndIf
	Int arousal = framework.GetActorArousal(player)
	If arousal > 100
		arousal = 100
	ElseIf arousal < 0
		arousal = 0
	EndIf

	; Claim it; anything newer bumps tweenGen and this loop stops cleanly.
	tweenGen += 1
	Int myGen = tweenGen

	; Step count IS the hitch budget -- each step is a full mesh rebuild.
	; 5 over ~1s reads as smooth; 10 cost double for no visible gain.
	Int steps = 5
	Int s = 1
	While s <= steps && myGen == tweenGen
		Float f = from + (target - from) * s / steps
		SetActorMorphs(player, arousal, f)
		PlayerArmorScale = f
		Utility.Wait(0.2)
		s += 1
	EndWhile

	; Pin the exact target if we weren't superseded.
	If myGen == tweenGen
		SetActorMorphs(player, arousal, target)
		PlayerArmorScale = target
	EndIf
EndFunction
