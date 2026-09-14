ScriptName ABM_Quest extends Quest
{Hosts all state for Aroused BodyMorphs.}

ABM_PlayerAlias Property PlayerAlias Auto

bool Property isNioOk = false Auto Hidden
bool Property isSLAroused28 = false Auto Hidden
bool Property isSLAroused29 = false Auto Hidden

; Master on/off switch. False = fully dormant: poll unregistered, handlers
; bail, UpdateActor refuses to write. Switching off also clears every morph we
; own, so the body returns to its BodySlide baseline rather than freezing.
bool Property ModEnabled = true Auto Hidden

bool Property DebugMode = false Auto Hidden
bool Property IgnoreMales = true Auto Hidden

; NPC filters, all defaulting TRUE (living humanoid NPCs only).
; "Beast" = engine-level creature (race WITHOUT ActorTypeNPC), not the playable
; beast races, which carry it and stay under IgnoreMales. GetSex() is only
; -1/0/1 and does NOT encode creature-ness -- hence the race keyword.
bool Property IgnoreDead         = true Auto Hidden
bool Property IgnoreMaleBeast    = true Auto Hidden
bool Property IgnoreFemaleBeast  = true Auto Hidden

; Scale morphs down by UnderArmorScale while the chest is covered, so fitted
; nipples don't clip. "Covered" = cuirass / body-clothing keyword, unless
; Advanced Nudity Detection flags the actor Topless/Nude. See IsTopCovered.
; The player refreshes on equip/unequip; NPCs on the next heartbeat.
bool Property SuppressUnderArmor = true Auto Hidden

; Multiplier applied while covered: 0.0 = fully flat (no clipping), 1.0 = no
; reduction.
float Property UnderArmorScale = 0.0 Auto Hidden
float Property DefaultUnderArmorScale = 0.0 AutoReadOnly Hidden

string[] Property MorphNames Auto Hidden
float[] Property MaxValue Auto Hidden
float[] Property MaxDefault Auto Hidden

; Install defaults = the "Natural" tier (matches IntensityPresets\Natural.json).
; AutoReadOnly = compiled constants, not cosave-persisted, so an updated .pex
; changes these on existing saves without touching the user's tuned sliders.
float Property DefaultSize = -0.4 AutoReadOnly Hidden
float Property DefaultLength = 0.5 AutoReadOnly Hidden
float Property DefaultCone = 0.8 AutoReadOnly Hidden
float Property DefaultArea = 0.0 AutoReadOnly Hidden

; Player poll interval (s). SLA only broadcasts every ~120s, so this keeps the
; player responsive mid-scene. 0 = heartbeat only.
float Property PollInterval = 5.0 Auto Hidden
float Property DefaultPollInterval = 5.0 AutoReadOnly Hidden

; NPC cell-scan radius (units) for every nearby sweep. 1000 ~= one room;
; MCM range 100 to 10000 (full exterior cell).
float Property ScanCellRadius = 1000.0 Auto Hidden
float Property DefaultScanCellRadius = 1000.0 AutoReadOnly Hidden

; Last-selected preset name. Display only -- the values are loaded into
; MaxValue[] at selection time. "Natural" by default because the built-in
; defaults ARE that tier, so a fresh install reports honestly.
String Property IntensityPreset = "Natural" Auto Hidden



Event OnInit()
	{First-time setup; runs once.}
	Debug.Notification("Aroused BodyMorphs: first time initialization")
	Debug.Trace("ABM: first time initialization")

	; Shares the reset path with the MCM's "Reset all state". DELIBERATELY does
	; NOT call back into the MCM: OnInit can fire during MCM registration, and
	; the cross-script lock contention froze the game in the predecessor mod.
	ResetAllState()

	Debug.Notification("Aroused BodyMorphs: initialization complete")
	debug.Trace("ABM: initialization complete")
EndEvent

Function ResetAllState()
	{Wipe persisted state back to install defaults. From OnInit, and from the
	 MCM's "Reset all state" to recover from corrupt / upgrade-stale state (None
	 arrays, mismatched counts, flags stuck false). Toggles are overwritten too,
	 since the cosave can hold arbitrary values from an older version.}
	; Sets MorphNames, MaxValue, MaxDefault.
	ApplyMorphSet()

	; Toggles + sliders back to their declared defaults.
	ModEnabled        = true
	DebugMode         = false
	IgnoreMales       = true
	IgnoreDead        = true
	IgnoreMaleBeast   = true
	IgnoreFemaleBeast = true
	PollInterval      = DefaultPollInterval
	ScanCellRadius    = DefaultScanCellRadius
	; The rebuilt slider values ARE the Natural tier, so label them as such.
	IntensityPreset   = "Natural"
	SuppressUnderArmor = true
	UnderArmorScale   = DefaultUnderArmorScale

	; Refresh the requirement flags against the live framework, and on first
	; install register the mod events + poll.
	PlayerAlias.OnPlayerLoadGame()
EndFunction

Function ResetDefaults()
	{Rebuild MaxDefault to match the current MorphNames. Derived from
	 DefaultForMorph, so it stays right for imported tables too (unknown -> 0).}
	MaxDefault = new float[128]
	Int i = 0
	While i < 128 && MorphNames[i] != ""
		MaxDefault[i] = DefaultForMorph(MorphNames[i])
		i += 1
	EndWhile
EndFunction

String[] Function FullMorphSet()
	{The full CBBE 3BA slider list. Single source for ApplyMorphSet and
	 EnsureFullMorphSet so they can't drift. The MCM groups by area at draw
	 time, so this order only decides ordering within a group.}
	String[] names = new String[23]
	names[0]  = "NippleSize"
	names[1]  = "NippleLength"
	names[2]  = "NipplePerkiness"
	names[3]  = "AreolaSize"
	names[4]  = "nippleperkmanga"
	names[5]  = "nippletube_v2"
	names[6]  = "innieoutie"
	names[7]  = "labianeat_v2"
	names[8]  = "labiatightup"
	names[9]  = "labiapuffyness"
	names[10] = "labiamorepuffyness_v2"
	names[11] = "labiaprotrude"
	names[12] = "labiaprotrude2"
	names[13] = "labiaprotrudeback"
	names[14] = "labiaspread"
	names[15] = "labiacrumpled_v2"
	names[16] = "labiabulgogi_v2"
	names[17] = "vaginasize"
	names[18] = "vaginahole"
	names[19] = "clit"
	names[20] = "clitswell_v2"
	names[21] = "cutepuffyness"
	names[22] = "cbpc"
	Return names
EndFunction

Function ApplyMorphSet()
	{Rebuild the whole table at default values -- install / Reset only. Does NOT
	 preserve tuning; use EnsureFullMorphSet for a non-destructive upgrade.
	 Morphs the body doesn't define are no-ops.}
	MorphNames = new String[128]
	MaxValue   = new float[128]

	String[] full = FullMorphSet()
	Int i = 0
	While i < full.Length
		MorphNames[i] = full[i]
		MaxValue[i]   = DefaultForMorph(full[i])
		i += 1
	EndWhile

	ResetDefaults()
EndFunction

Function EnsureFullMorphSet()
	{Non-destructive upgrade: append missing morphs, preserving existing tuning.
	 No caller yet -- kept so a future FullMorphSet addition can reach old saves
	 without wiping their sliders.}
	String[] full = FullMorphSet()
	Int count = MorphCount()
	Int i = 0
	While i < full.Length
		count = AddMorphIfMissing(full[i], count)
		i += 1
	EndWhile
	ResetDefaults()
EndFunction

Int Function AddMorphIfMissing(String morphName, Int count)
	{Append morphName if absent, returning the new count. Bounded to 128.}
	If count >= 128
		Return count
	EndIf
	Int i = 0
	While i < count
		If MorphNames[i] == morphName
			Return count
		EndIf
		i += 1
	EndWhile
	MorphNames[count] = morphName
	MaxValue[count]   = DefaultForMorph(morphName)
	Return count + 1
EndFunction

Float Function DefaultForMorph(String morphName)
	{Per-morph defaults (Natural tier -- keep in sync with Natural.json). Nipples
	 use the Default* properties; the genital set lists only non-zero values;
	 everything else defaults to 0.}
	If morphName == "NippleSize"
		Return DefaultSize
	ElseIf morphName == "NippleLength"
		Return DefaultLength
	ElseIf morphName == "NipplePerkiness"
		Return DefaultCone
	ElseIf morphName == "AreolaSize"
		Return DefaultArea
	ElseIf morphName == "innieoutie"
		Return 0.1
	ElseIf morphName == "labiapuffyness"
		Return 0.1
	ElseIf morphName == "labiaprotrude"
		Return 0.2
	ElseIf morphName == "clit"
		Return 0.4
	ElseIf morphName == "clitswell_v2"
		Return 0.6
	ElseIf morphName == "cutepuffyness"
		Return 0.1
	EndIf
	Return 0.0
EndFunction

Int Function MorphCount()
	{Populated morph slots. The MCM syncs its render/handler count to this.}
	Int i = 0
	While i < 128 && MorphNames[i] != ""
		i += 1
	EndWhile
	Return i
EndFunction

Int Function GroupForMorph(String morphName)
	{Area group inferred from the name, so imported morphs sort themselves:
	 0 Nipples, 1 Areolas, 2 Vagina, 3 Other. Find is case-insensitive, and
	 order is priority -- "nipple" wins over "areola" in one name.}
	If StringUtil.Find(morphName, "nipple") >= 0
		Return 0
	ElseIf StringUtil.Find(morphName, "areola") >= 0
		Return 1
	ElseIf StringUtil.Find(morphName, "labia") >= 0 || StringUtil.Find(morphName, "vagina") >= 0 || StringUtil.Find(morphName, "clit") >= 0 || StringUtil.Find(morphName, "innie") >= 0 || StringUtil.Find(morphName, "cute") >= 0
		Return 2
	EndIf
	Return 3
EndFunction

String Function GroupName(Int groupId)
	{Display name of an area group (MCM section headers).}
	If groupId == 0
		Return "$ABM_Group_Nipples"
	ElseIf groupId == 1
		Return "$ABM_Group_Areolas"
	ElseIf groupId == 2
		Return "$ABM_Group_Vagina"
	EndIf
	Return "$ABM_Group_Other"
EndFunction
