ScriptName ABM_PlayerAlias extends ReferenceAlias
{Player alias: requirements detection, event handling, and the morph writer.}

ABM_Quest Property MainQuest Auto

; RaceMenu / SKEE version gates for the BodyMorph API
Int Property SKEE_VERSION = 1 AutoReadOnly
Int Property NIOVERRIDE_SCRIPT_VERSION = 6 AutoReadOnly

; Every BodyMorph this mod writes is registered under this key, so ClearActorMorphs
; can remove exactly our morphs and nothing else.
String Property NIO_KEY = "ArousedBodyMorphs.esp" AutoReadOnly hidden

slaFrameworkScr Property sla_Framework Auto

; --- Top-nudity / armor-suppression state ---
; Resolved fresh on every load by ResolveNudityDetection(). IsTopCovered uses the
; vanilla ArmorCuirass / ClothingBody worn-keyword check as primary; when Advanced
; Nudity Detection ("Advanced Nudity Detection.esp") is present its Topless/Nude
; faction ranks (the same formIDs SLA NG resolves -- see slamainscr.psc) only
; OVERRIDE a covered result to bare, so skimpy / bikini tops are judged correctly
; without breaking on actors AND hasn't scanned. See IsActorNaked in slamainscr.psc.
Bool AND_Resolved = false
Faction AND_Nude
Faction AND_Topless
Keyword kwArmorCuirass
Keyword kwClothingBody

; Player-only reveal-tween state. PlayerArmorScale is the armor scale last applied
; to the player (the tween's start point); tweenGen is bumped by any direct player
; update (poll / heartbeat / a newer equip change) so an in-flight tween bails
; instead of fighting it.
Float PlayerArmorScale = 1.0
Int tweenGen = 0

; Arousal value last actually WRITTEN to the player by UpdateActor. Reported by
; PokePlayerArousal so the MCM's check row shows the number that was applied,
; not a second, independently-read one.
Int PlayerLastArousal = 0

; Generation counter for RefreshOnArmorChange: a redress fires one equip event
; per item and the handlers serialize on this script, each paying the 0.3s AND
; settle -- bumping this on entry lets every stale queued handler bail after
; its wait, so only the newest event does the refresh.
Int armorGen = 0

; NativeActive() resolved once per load. Both inputs (DLL registered with
; SKSE, backend+SKEE detected at kDataLoaded) can only change with a game
; restart, so paying two native calls per actor per sweep to re-ask was pure
; waste. Refreshed in OnPlayerLoadGame via ResolveNativeMode().
Bool nativeMode = false

; ActorTypeNPC keyword (Skyrim.esm), resolved per load in
; ResolveNudityDetection. A race without it is an engine-level creature --
; this is the creature test for the beast filters. ActorBase.GetSex() only
; returns -1/0/1 (None/Male/Female; see the game's own ActorBase.psc), it
; does NOT encode creature-ness.
Keyword kwActorTypeNPC

Event OnInit()
	{Fires once when the alias is first filled. Warm the sla_Framework cache
	 eagerly so the manual OnPlayerLoadGame call from Quest.OnInit (and every
	 subsequent use) takes the fast path. Return value discarded -- side
	 effect (Auto property population) is what we want.}
	GetFramework()
EndEvent

Bool Function NativeActive()
	{True when the OPTIONAL ArousedBodyMorphs.dll is installed AND it detected a
	 native arousal backend (SLA NG's C API / OSL Aroused's exports) plus SKEE.
	 In that state the DLL owns the whole update pipeline -- event-driven
	 per-actor refreshes, the player poll, armor-change refreshes, morph writes
	 -- and every Papyrus pipeline path here stands down. Without the DLL (or on
	 a legacy Papyrus-only SLA fork) this is false and nothing changes.
	 Cached per load (ResolveNativeMode): called once per actor in every sweep,
	 and the answer can only change with a game restart.}
	Return nativeMode
EndFunction

Function ResolveNativeMode()
	{The actual DLL probe behind NativeActive(). Two native calls; the &&
	 short-circuits, so ABM_Native.IsActive (unbound without the DLL) is never
	 reached when the DLL is absent. Called from OnPlayerLoadGame -- which
	 ResetAllState also routes through -- so the cache refreshes on every load
	 and on first install.}
	nativeMode = ABM_Native.IsInstalled() && ABM_Native.IsActive()
EndFunction

Function PushConfigToNative()
	{Mirror the quest's option block + morph table into the native DLL. The MCM
	 stays the single source of truth; this is called on every load, from
	 SetModEnabled / RestartPolling, and when the MCM closes, so the DLL always
	 works from current values. No-op without the DLL.}
	If !ABM_Native.IsInstalled()
		return
	EndIf
	ABM_Native.PushConfig(MainQuest.ModEnabled, MainQuest.IgnoreMales, MainQuest.IgnoreDead, MainQuest.IgnoreMaleBeast, MainQuest.IgnoreFemaleBeast, MainQuest.SuppressUnderArmor, MainQuest.UnderArmorScale, MainQuest.PollInterval, MainQuest.ScanCellRadius, MainQuest.DebugMode)
	ABM_Native.PushMorphTable(MainQuest.MorphNames, MainQuest.MaxValue)
EndFunction

slaFrameworkScr Function GetFramework()
	{Defensive accessor for the SLA framework script. Used in three modes:

	   (1) OnInit -- warm-cache the Auto property on first-fill.
	   (2) OnPlayerLoadGame -- double-check on every load (catches SLA reinstall
	       / formID rewire since the cosaved Auto value was last set).
	   (3) Call sites (OnArousalComputed scan, UpdateActor arousal read,
	       OnPlayerLoadGame version check) -- get the framework safely. Cheap
	       when sla_Framework is already populated (one bool check + return).

	 Falls back to Quest.GetQuest("sla_Framework") if the Auto property is None
	 -- both SLA NG / SLO Aroused NG and OSL Aroused's stub ship a quest with
	 that editor ID, per the SLA NG readme's portable detection pattern.

	 On successful fallback, populates the Auto property so subsequent calls
	 take the fast path and the resolved value persists in the cosave for the
	 next save load.

	 Why this exists: this mod's predecessor ESP has been observed in the
	 wild with the sla_Framework Auto property silently unwired -- callers got
	 None from the property even when SLA was loaded and the quest was alive in
	 memory. The dynamic lookup ignores the ESP wiring and goes straight to the
	 named quest.}
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
	{Checking requirements every game load. Also re-runs GetFramework to
	 catch SLA reinstall / formID rewire since the cached Auto property was set.}
	; Double-check the framework property on every load. If the cosaved Auto
	; property is still valid (normal case) this is a no-op; if SLA was
	; reinstalled with different formIDs it'll re-populate via the fallback.
	GetFramework()

	; Refresh the cached NativeActive() answer -- DLL install/uninstall needs a
	; game restart, so once per load is exactly often enough. Done before the
	; abort paths below so the armor-change handlers see the right mode even
	; when requirements fail.
	ResolveNativeMode()

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

	; Multi-fork detection via slaframeworkscr.GetVersion() (portable -- both OSL
	; Aroused's stub framework and real SLA NG implement it). Date-stamped scheme:
	;   OSL Aroused stub      -> 20140124   (read-only API; GetActorArousal works,
	;                                        slaSet/ModArousalEffect ModEvents do not)
	;   SLAXSE2022            -> 20190720   (legacy)
	;   SexLab Aroused NG     -> >= 20200000 (NG-branded / SLO Aroused NG, packs
	;                                         MMmmppp e.g. 30100010 for 3.1.10)
	; The official "is this real NG?" gate per SLA NG's README is >= 20200000.
	; This mod only consumes the read path (GetActorArousal) which is portable
	; across forks, so legacy / stub installs still work for morph display.
	; Defensive accessor -- GetFramework() at the top of OnPlayerLoadGame already
	; warmed/refreshed the cache, but going through the accessor here means a
	; mid-session re-entry (e.g. ResetAllState -> alias.OnPlayerLoadGame from the
	; MCM thread before OnInit's cache was committed) still resolves cleanly.
	slaFrameworkScr framework = GetFramework()
	if !framework
		; Both the Auto property AND the Quest.GetQuest fallback came back None.
		; Real-world this means SexLabAroused.esm isn't loaded at all. Without it
		; we cannot detect the fork or read arousal -- abort.
		MainQuest.isSLAroused28 = false
		MainQuest.isSLAroused29 = false
		debug.Notification("Aroused BodyMorphs: SLA framework not found (Auto property unwired AND Quest.GetQuest fallback failed), aborting")
		debug.Trace("ABM: SLA framework not found (Auto property unwired AND Quest.GetQuest fallback failed), aborting")
		return
	endif
	int slaVersion = framework.GetVersion()

	if slaVersion >= 20200000
		; Real SLA NG (or compatible >= NG-class fork).
		MainQuest.isSLAroused28 = false
		MainQuest.isSLAroused29 = true
	elseif slaVersion > 0
		; OSL Aroused stub, SLAXSE2022, eXtended LE, original SSELoose, or any
		; other pre-NG fork. Still routes through GetActorArousal so reads work.
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

	; Resolve AND factions + vanilla body keywords for the under-armor suppression.
	; Re-run every load so an AND install/uninstall since the last save is picked up.
	ResolveNudityDetection()

	RegisterForModevent("sla_UpdateComplete", "OnArousalComputed")

	; Hand the current settings to the optional native DLL (no-op without it).
	PushConfigToNative()

	; Player-only polling refresh. SLA NG only fires sla_UpdateComplete on its
	; scheduled scan (default 120s); polling here keeps the player's morphs
	; responsive to mid-scene arousal changes (OSL/OStim, denial ramps, etc.)
	; without lowering SLA's global scan frequency. Skipped entirely while the
	; mod is switched off in the MCM -- the mod event registrations above are
	; kept (their handlers bail on the ModEnabled gate), but there is no reason
	; to burn an OnUpdate tick every few seconds for a dormant mod. Also skipped
	; when the native DLL is active: it runs its own poll/event pipeline.
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
		; Switched off in the MCM, or the requirements were lost (SLA / RaceMenu
		; uninstalled mid-save) -- stop polling. Re-armed by RestartPolling,
		; SetModEnabled, or the next OnPlayerLoadGame.
		return
	EndIf
	If NativeActive()
		; The DLL polls / receives events itself -- let the Papyrus loop die.
		return
	EndIf

	UpdateActor(Game.GetPlayer(), false)

	Float pollInterval = MainQuest.PollInterval
	If pollInterval > 0.0
		RegisterForSingleUpdate(pollInterval)
	EndIf
EndEvent

Function RestartPolling()
	{Called from MCM when the user changes PollInterval. Cancels any pending tick
	 and re-arms at the current interval so the change takes effect immediately
	 (and so dialing 0 -> non-zero can restart a stopped poll loop). In native
	 mode the push alone suffices -- the DLL re-reads its interval on push.}
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
	{Single gate for every code path that writes morphs: the mod must be switched
	 on in the MCM AND its requirements must be satisfied. Cheap (three property
	 reads, && short-circuits), so it is fine to call per tick / per actor.}
	Return MainQuest.ModEnabled && MainQuest.isNioOk && (MainQuest.isSLAroused28 || MainQuest.isSLAroused29)
EndFunction

Function SetModEnabled(Bool enabled)
	{MCM entry point for the master on/off toggle. Owns the whole transition so the
	 switch takes effect immediately instead of on the next heartbeat:

	   off -> on : re-apply the morphs now and re-arm the poll loop.
	   on -> off : stop the poll loop and CLEAR every morph this mod wrote, so the
	               body snaps back to its BodySlide baseline. Leaving them frozen at
	               the last-applied value would make "disabled" indistinguishable
	               from "stuck", which is exactly what the toggle exists to rule out.

	 Both directions cover the player AND the aroused NPCs in scan range, so the
	 switch reads the same on everyone -- re-applying only the player would leave
	 nearby NPCs flat until SLA's next heartbeat (up to 120s).

	 tweenGen is bumped first: a reveal tween in flight (TweenPlayerReveal) would
	 otherwise keep writing morphs for up to a second after we cleared them. The
	 ModEnabled write happens before either branch, so SetActorMorphs' own gate
	 also shuts out a tween that wakes up mid-transition.}
	tweenGen += 1
	MainQuest.ModEnabled = enabled
	; Native DLL first: its poll thread and event sinks gate on the pushed
	; ModEnabled, so the switch reaches them before we re-apply or clear.
	PushConfigToNative()
	If enabled
		Bool doDebug = MainQuest.DebugMode
		UpdateActor(Game.GetPlayer(), doDebug)
		UpdateNearbyActors(doDebug)
		RestartPolling()
	Else
		UnregisterForUpdate()
		ClearAllMorphs()
	EndIf
EndFunction

Actor[] Function ScanNearbyAroused(Bool ignoreDead)
	{The aroused NPCs around the player, or None when SLA can't be queried. Shared by
	 the SLA heartbeat and by both directions of the master switch so the three agree
	 on which actors count as "nearby".

	 slaArousal is itself an Auto property on slaframeworkscr -- if SLA's own ESP is
	 broken-wired the same way ours has been seen to be, this comes back None and
	 MiscUtil.ScanCellNPCsByFaction(None, ...) is unspecified, so bail instead.}
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
	Return MiscUtil.ScanCellNPCsByFaction(framework.slaArousal, Game.GetPlayer(), MainQuest.ScanCellRadius, 0, 127, ignoreDead)
EndFunction

Function UpdateNearbyActors(Bool doDebug)
	{Push morphs to the aroused NPCs in scan range. Used when the mod is switched back
	 on, so NPCs come back at the same moment the player does.}
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
	{Drop every morph registered under our NIO key for this actor and push the model
	 update. Only our key is touched, so morphs owned by other mods (or the user's
	 own RaceMenu sliders) survive untouched.

	 In native mode the clear goes through the DLL, so the whole write path stays
	 on one side of the fence (and on the main thread) rather than half of it
	 reaching into SKEE from the VM.}
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
	{Remove this mod's morphs from the player and from the aroused NPCs currently in
	 scan range. Used when the mod is switched off in the MCM.

	 The isNioOk bail is not just an optimisation: the master toggle is deliberately
	 never greyed out (it has to stay usable to get back out of the disabled state),
	 so it can be clicked on an install with no SKEE at all -- where these natives
	 have no implementation to bind to. Nothing was ever written in that state, so
	 there is nothing to clear.

	 IgnoreDead is deliberately false here (unlike the heartbeat scan): a corpse that
	 was morphed while alive still carries our morphs and should be cleaned up too.
	 NPCs outside ScanCellRadius keep their last morph values until they come back
	 into range with the mod re-enabled -- unavoidable without a global actor sweep,
	 and called out in the MCM info text.}
	PlayerArmorScale = 1.0
	PlayerLastArousal = 0
	If !MainQuest.isNioOk
		return
	EndIf
	ClearActorMorphs(Game.GetPlayer())

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
	{MCM helper for the "Player arousal" row: re-apply the player's morphs right now
	 and report what was written. Returns the arousal actually applied (0..100), or a
	 negative sentinel the MCM renders as its own label:
	   -1  SLA framework unavailable (nothing to read).
	   -2  UpdateActor declined to write -- the actor filters excluded the player
	       (male PC with Ignore males on, dead, etc). Reporting an arousal number
	       here would be a false pass: no morphs were applied.
	   -3  The mod is switched off in the MCM ("Mod enabled"), so nothing is written
	       by design.
	 The returned value is the one UpdateActor wrote (via PlayerLastArousal), not a
	 second independent GetActorArousal read, so the row can't disagree with the body.}
	If !MainQuest.ModEnabled
		Return -3
	EndIf
	If !GetFramework()
		Return -1
	EndIf
	If !UpdateActor(Game.GetPlayer(), MainQuest.DebugMode)
		Return -2
	EndIf
	Return PlayerLastArousal
EndFunction

Bool Function CheckNiOverride()
	Return SKSE.GetPluginVersion("skee") >= SKEE_VERSION && NiOverride.GetScriptVersion() >= NIOVERRIDE_SCRIPT_VERSION
EndFunction

Function ResolveNudityDetection()
	{Resolve the Advanced Nudity Detection factions (top-nudity integration) and
	 the vanilla body keywords (no-AND fallback). Called from OnPlayerLoadGame on
	 every load so an AND install/uninstall since the last save is reflected.

	 The AND formIDs (0x831 Nude, 0x832 Topless) and ESP name match what SLA NG
	 itself resolves in slamainscr.psc -- AND owns these factions, not SLA, so we
	 can read them directly regardless of which SLA fork is installed.}
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
	{True when the actor's chest is covered, so nipple/areola morphs should be
	 scaled down (prevents clipping through tops).

	 Mirrors SexLab Aroused's own naked test (slamainscr.IsActorNaked): the vanilla
	 ArmorCuirass / ClothingBody worn-keyword check is primary, and Advanced Nudity
	 Detection only OVERRIDES a "covered" result to bare. We deliberately do NOT make
	 AND the sole authority: AND's NPC factions are only populated by its periodic,
	 player-cast NPCScanSpell (MCM-gated via ScanNPC), so an unscanned / out-of-range
	 / just-stripped NPC has no Topless rank yet -- trusting AND alone would suppress
	 morphs on a genuinely naked NPC (e.g. mid-scene). The keyword check is per-actor
	 and immediate, so bare actors always show regardless of AND's scan coverage.

	 Reading the faction rank is cheap (a rank lookup); we never call SLA's expensive
	 IsActorNaked(). Naked-body armors / SOS carry neither keyword, so they read bare.}
	; No top worn at all -> bare chest. True for every actor with no dependency on
	; AND having scanned them.
	If !(who.WornHasKeyword(kwArmorCuirass) || who.WornHasKeyword(kwClothingBody))
		Return false
	EndIf
	; A top is worn. Let AND override to "bare" for skimpy / bikini / transparent
	; tops that still carry a cuirass keyword but expose the chest.
	If AND_Resolved
		If (AND_Nude && who.GetFactionRank(AND_Nude) == 1) || (AND_Topless && who.GetFactionRank(AND_Topless) == 1)
			Return false
		EndIf
	EndIf
	Return true
EndFunction

Event OnObjectEquipped(Form akBaseObject, ObjectReference akReference)
	{Player put something on -- suppress immediately (snap, no ease) so the chest
	 morphs collapse before anything can clip during a redress.}
	RefreshOnArmorChange(akBaseObject, false)
EndEvent

Event OnObjectUnequipped(Form akBaseObject, ObjectReference akReference)
	{Player took something off -- if that bares the chest, ease the morphs back in.}
	RefreshOnArmorChange(akBaseObject, true)
EndEvent

Function RefreshOnArmorChange(Form akBaseObject, Bool wasRemoved)
	{Player-only morph refresh when armor is equipped/unequipped. Gated on the same
	 requirements as the poll loop so we never poke NiOverride when the mod is
	 non-functional. With AND, a top change can come from many slots, so we react to
	 any worn armor (after a short settle so AND updates its factions first); without
	 AND only body-slot (32) armor can change the covered state.

	 Removing armor that leaves the chest bare eases the morphs in over ~1s
	 (TweenPlayerReveal); every other case snaps via UpdateActor -- notably equipping,
	 so nipples flatten instantly rather than poking through a redress.}
	If NativeActive()
		; The DLL's TESEquipEvent sink refreshes the player on armor changes.
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
	; Debounce: a redress fires one equip event per item, and Utility.Wait
	; unlocks the script, so the queued handlers overlap here. Claim the
	; refresh; any newer armor event bumps armorGen, and every superseded
	; handler bails after its wait instead of stacking N identical
	; UpdateActor passes -- the newest event sees the final worn state.
	armorGen += 1
	Int myGen = armorGen
	If AND_Resolved
		Utility.Wait(0.3)  ; let AND update its nudity factions first
		If myGen != armorGen
			return
		EndIf
	EndIf

	If wasRemoved && !IsTopCovered(Game.GetPlayer())
		TweenPlayerReveal()
	Else
		UpdateActor(Game.GetPlayer(), MainQuest.DebugMode)
	EndIf
EndFunction

Event OnArousalComputed(string eventName, string argString, float argNum, form sender)
	{SLA broadcast at the end of each scan tick. Refresh the player, then any nearby aroused NPCs.}
	If !MainQuest.ModEnabled
		; Switched off in the MCM. The mod event registration is only (re)made on
		; game load, not on the toggle, so the gate lives here.
		return
	EndIf
	If NativeActive()
		; The DLL sinks sla_UpdateComplete itself and sweeps player + nearby
		; NPCs natively -- doing it here too would just double the work.
		return
	EndIf
	bool doDebug = MainQuest.DebugMode
	If doDebug
		debug.Notification("Aroused BodyMorphs: Arousal event")
		debug.Trace("ABM: Arousal event")
	EndIf

	UpdateActor(Game.GetPlayer(), doDebug)

	If argNum <= 0
		If doDebug
			debug.Notification("Aroused BodyMorphs: No aroused NPCs nearby, updating player only")
			debug.Trace("ABM: No aroused NPCs nearby, updating player only")
		EndIf
		return
	EndIf

	; ScanNearbyAroused re-resolves the framework defensively (mid-session SLA
	; reinstall, cosmetically unwired Auto property) and returns None if SLA
	; can't be queried at all -- skip the tick rather than poke PapyrusUtil
	; with a null faction.
	Actor[] theActors = ScanNearbyAroused(MainQuest.IgnoreDead)
	If !theActors
		return
	EndIf
	; theActors can have null slots if SLA's faction-rank cache is mid-update.
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

	 Returns true when the actor's morphs now reflect their arousal (written, or
	 verified already at the target values and skipped), false on every bail-out
	 (null actor, no ActorBase, excluded by an Ignore filter, no SLA framework).
	 Callers that just want the side effect can discard it; PokePlayerArousal
	 uses it so the MCM check row can't report a pass on a skipped actor.}
	If !who
		; OnArousalComputed guards its array entries, but the debug spell's
		; crosshair fallback and any third-party script that ends up here can
		; still pass None. Bail rather than null-deref.
		return false
	EndIf
	If !MainQuest.ModEnabled
		; Master switch off. Belt and braces: the event handlers already bail, but
		; the debug spell and any third-party caller reach UpdateActor directly.
		return false
	EndIf
	If NativeActive()
		; Route every Papyrus-initiated update (debug spell, MCM "Check now")
		; through the DLL: one native call does the filters, the fresh arousal
		; read, under-armor scaling and all SKEE writes.
		Int applied = ABM_Native.UpdateActor(who)
		If who == Game.GetPlayer()
			tweenGen += 1
			If applied >= 0
				PlayerLastArousal = applied
			EndIf
		EndIf
		return applied >= 0
	EndIf
	ActorBase whoBase = who.GetLeveledActorBase()
	If !whoBase
		; LeveledActorBase can return None for actors in unusual states (e.g.
		; mid-spawn). No way to filter by sex / IsDead without it -- skip.
		return false
	EndIf
	; ActorBase.GetSex() returns -1 None / 0 Male / 1 Female -- and nothing
	; else (see the game's own ActorBase.psc; the old 2/3-for-creatures scheme
	; this filter once tested for does not exist, which made the beast toggles
	; dead code and let female creatures through every filter). Creature-ness
	; comes from the race instead: no ActorTypeNPC keyword = engine-level
	; creature. Same split the native DLL uses, so both modes now agree.
	; Sex -1 (None) is treated as male, matching the DLL's kFemale test.
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
		; Dead NPCs are already filtered out at the OnArousalComputed cell-scan
		; level (we pass IgnoreDead into ScanCellNPCsByFaction), but the player
		; poll and the debug spell can still hit this path with a corpse target,
		; so we re-check here.
		skipReason = "is dead"
	EndIf
	If skipReason != ""
		If doDebug
			debug.Notification("Aroused BodyMorphs: "+whoBase.GetName()+" "+skipReason+", skipping")
			debug.Trace("ABM: "+whoBase.GetName()+" "+skipReason+", skipping")
		EndIF
		return false
	EndIf

	; Portable per-actor arousal read (works on SLA NG, SLO, OSL Aroused, eXtended).
	; GetActorArousal -> slaInternalModules.GetArousal(who), which triggers a fresh
	; recalculation rather than returning the cached faction-rank that SLA only
	; refreshes on its scan tick. Already clamped to [0,100] by GetActorArousal.
	; Defensive accessor: GetFramework() normally just returns the cached
	; sla_Framework Auto property (warmed in OnInit / OnPlayerLoadGame), but
	; falls back to Quest.GetQuest if the property somehow became None at
	; runtime. Cheap when the cache is valid -- one bool check + return.
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

	; Under-armor suppression. When the chest is covered, scale every morph by
	; UnderArmorScale (0.0 = flat, no clip; 1.0 = full) so fitted nipples don't
	; poke through tops. IsTopCovered prefers Advanced Nudity Detection's
	; Topless/Nude state, falling back to the vanilla worn-keyword check.
	Float armorScale = 1.0
	If MainQuest.SuppressUnderArmor && IsTopCovered(who)
		armorScale = MainQuest.UnderArmorScale
		If doDebug
			debug.Notification("Aroused BodyMorphs: "+whoBase.GetName()+" chest covered, scaling morphs x"+armorScale)
			debug.Trace("ABM: "+whoBase.GetName()+" chest covered, scaling morphs x"+armorScale)
		EndIf
	EndIf

	Bool isPlayer = who == Game.GetPlayer()
	SetActorMorphs(who, Arousal, armorScale, doDebug)

	; Track the player's last-applied scale (the reveal tween's start point) and
	; arousal (reported by PokePlayerArousal), and cancel any in-flight tween --
	; a direct update supersedes it.
	If isPlayer
		PlayerArmorScale = armorScale
		PlayerLastArousal = Arousal
		tweenGen += 1
	EndIf
	return true
EndFunction

Function SetActorMorphs(Actor who, Int arousal, Float scale, Bool doDebug=false)
	{Write every morph = maxValue * arousal/100 * scale, then push the model update.
	 Shared by UpdateActor (a single snap) and TweenPlayerReveal (one step of the
	 reveal ease). Iterates the morph table until the first empty slot; honours
	 imported counts up to 128. Papyrus && short-circuits, so MorphNames[j] is not
	 read once j hits 128.

	 Unchanged-value skip: arousal rarely moves between poll ticks, and the
	 UpdateModelWeight mesh rebuild is by far the most expensive call in the mod,
	 so re-writing identical values every tick was the dominant steady-state cost.
	 Every slot is maxValue[j] * factor -- one shared factor -- so a single slot
	 settles whether anything would change, and one GetBodyMorph read replaces
	 23 writes plus the rebuild.

	 The probe asks NiOverride what WE last wrote (our key only), rather than
	 trusting a remembered value: NiOverride is then the single source of truth,
	 so there is no cache to invalidate when the MCM retunes a slider, when a
	 save is loaded, or if anything else clears our key -- the comparison target
	 moves with the settings and a mismatch always rewrites. GetBodyMorph returns
	 0.0 for an actor we never touched, so a never-aroused bystander at factor 0
	 costs exactly one call and no rebuild.

	 The ModEnabled check is here, at the single point where morphs are written,
	 because every external call in this file unlocks the script: the MCM thread can
	 enter SetModEnabled part-way through a tween step and clear the morphs, and
	 without this gate the rest of the step would paint them straight back on.}
	If !MainQuest.ModEnabled
		return
	EndIf
	String[] morphNames = MainQuest.MorphNames
	Float[]  maxValues  = MainQuest.MaxValue

	; Integer division trap: arousal / 100 would truncate to 0 -- cast first.
	Float factor = (arousal as Float) / 100.0 * scale

	; Probe slot = the first morph with a non-zero max. A zero-max slot always
	; reads 0 whatever the factor, so it could never detect a change.
	Int p = 0
	While p < 128 && morphNames[p] != "" && maxValues[p] == 0.0
		p += 1
	EndWhile
	If p >= 128 || morphNames[p] == ""
		; Empty table, or every max is 0 -- this table can never write anything.
		return
	EndIf
	; Tolerance is 1e-6: float32 noise around these magnitudes is ~1e-8, while
	; the smallest step a user can dial in (max 0.01, one arousal point) is
	; 1e-4 -- two orders of margin on both sides.
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
	{Gradually grow the player's morphs from the currently-applied armor scale up to
	 the now-uncovered target over ~1s, for a smooth reveal when body armor is
	 removed. Player-only. Arousal is read once and held constant across the short
	 tween. Overlap-guarded: bumps tweenGen and bails if a newer update (another
	 equip change, the poll, or the heartbeat) supersedes it mid-ease.}
	If !IsActive()
		; RefreshOnArmorChange checked this too, but it then waits 0.3s for Advanced
		; Nudity Detection -- long enough for the master switch to be flipped off in
		; between. Without this the tween would claim tweenGen (so SetModEnabled's
		; bump can't stop it) and re-apply morphs a second after they were cleared.
		return
	EndIf
	Actor player = Game.GetPlayer()
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

	; Claim this tween; a newer one (or any UpdateActor on the player) will bump
	; tweenGen and make the myGen check below fail, so this loop stops cleanly.
	tweenGen += 1
	Int myGen = tweenGen

	; 5 steps x 0.2s: each step is 23 SetBodyMorph calls plus a full
	; UpdateModelWeight mesh rebuild, so step count is the hitch budget --
	; 5 rebuilds over ~1s reads as smooth, 10 was double the cost for no
	; visible gain.
	Int steps = 5
	Int s = 1
	While s <= steps && myGen == tweenGen
		Float f = from + (target - from) * s / steps
		SetActorMorphs(player, arousal, f)
		PlayerArmorScale = f
		Utility.Wait(0.2)
		s += 1
	EndWhile

	; Pin the exact target if we ran to completion (weren't superseded).
	If myGen == tweenGen
		SetActorMorphs(player, arousal, target)
		PlayerArmorScale = target
	EndIf
EndFunction
