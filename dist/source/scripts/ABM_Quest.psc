ScriptName ABM_Quest extends Quest
{Hosts all state for Aroused BodyMorphs.}

ABM_PlayerAlias Property PlayerAlias Auto

bool Property isNioOk = false Auto Hidden
bool Property isSLAroused28 = false Auto Hidden
bool Property isSLAroused29 = false Auto Hidden

; Master on/off switch (MCM "Mod enabled", General page). When false the mod
; goes fully dormant: the player poll is unregistered, the SLA heartbeat /
; armor-change handlers bail immediately, and UpdateActor refuses to write.
; Switching it off also CLEARS every morph this mod owns
; (NIO key "ArousedBodyMorphs.esp") from the player and nearby NPCs, so the
; body returns to its BodySlide baseline rather than freezing at the last value.
; See ABM_PlayerAlias.SetModEnabled / IsActive / ClearAllMorphs.
bool Property ModEnabled = true Auto Hidden

bool Property DebugMode = false Auto Hidden
bool Property IgnoreMales = true Auto Hidden

; NPC filter toggles. All three default to TRUE -- skipping dead actors and
; creatures is the conservative default that matches typical user expectation
; (morph effect on living humanoid NPCs only). Tunable in MCM.
; Note: "Beast" here means engine-level creature actors (Skyrim's GetSex()
; returns 2 for male creatures and 3 for female creatures), NOT the playable
; beast races (Khajiit / Argonian / orc), which are GetSex() 0/1 and stay
; covered by IgnoreMales.
bool Property IgnoreDead         = true Auto Hidden
bool Property IgnoreMaleBeast    = true Auto Hidden
bool Property IgnoreFemaleBeast  = true Auto Hidden

; When true, arousal morphs are scaled down (by UnderArmorScale) on any actor
; whose chest is covered, so fitted nipples don't clip through the top. "Covered"
; = wearing a cuirass / body-clothing (vanilla keyword check), unless Advanced
; Nudity Detection is installed and flags the actor Topless/Nude (override for
; skimpy / bikini tops). See IsTopCovered in ABM_PlayerAlias.
; The player alias refreshes instantly on equip/unequip via OnObjectEquipped /
; OnObjectUnequipped; NPCs collapse on the next heartbeat/poll. Default ON.
bool Property SuppressUnderArmor = true Auto Hidden

; Multiplier (0.0 .. 1.0) applied to every arousal morph while the chest is
; covered (and SuppressUnderArmor is on). 0.0 = nipples fully flat under armor
; (no clipping); 1.0 = no reduction. MCM-tunable. Default 0.0.
float Property UnderArmorScale = 0.0 Auto Hidden
float Property DefaultUnderArmorScale = 0.0 AutoReadOnly Hidden

string[] Property MorphNames Auto Hidden
float[] Property MaxValue Auto Hidden
float[] Property MaxDefault Auto Hidden

; Install-default slider values = the "Natural" intensity tier (matches
; IntensityPresets\Natural.json exactly). AutoReadOnly = compiled constants,
; not cosave-persisted, so an updated .pex changes these on existing saves too
; (via the per-load ResetDefaults rebuild) without touching the user's tuned
; MaxValue sliders.
float Property DefaultSize = -0.4 AutoReadOnly Hidden
float Property DefaultLength = 0.5 AutoReadOnly Hidden
float Property DefaultCone = 0.8 AutoReadOnly Hidden
float Property DefaultArea = 0.0 AutoReadOnly Hidden

; Player-only morph poll interval (seconds). SLA NG only broadcasts
; sla_UpdateComplete on its scheduled scan (default 120s); polling the player
; in between keeps morphs responsive to mid-scene arousal changes from
; OSL/OStim, denial ramps, etc. Set to 0 in MCM to disable polling and
; fall back to the heartbeat-only behaviour.
float Property PollInterval = 5.0 Auto Hidden
float Property DefaultPollInterval = 5.0 AutoReadOnly Hidden

; NPC cell-scan radius (units) used by every nearby-NPC sweep
; (ABM_PlayerAlias.ScanNearbyAroused -- the SLA heartbeat and both directions
; of the MCM master switch). Default 1000 ~= one room.
; Range in MCM: 100 (very tight) to 10000 (full exterior cell).
float Property ScanCellRadius = 1000.0 Auto Hidden
float Property DefaultScanCellRadius = 1000.0 AutoReadOnly Hidden

; Last-selected intensity preset (Minimal / Natural / Noticeable / Exaggerated)
; from the MCM combobox. Display-only -- the actual values are loaded from
; SKSE\Plugins\StorageUtilData\ArousedBodyMorphs\IntensityPresets\<name>.json
; into MaxValue[] at selection time. Defaults to "Natural" because the built-in
; install defaults (DefaultForMorph) ARE the Natural tier, so a fresh install /
; Reset honestly shows "Natural".
String Property IntensityPreset = "Natural" Auto Hidden



Event OnInit()
	{First-time setup. Setting all defaults.}
	;Note: this initialization is performed only once.

	Debug.Notification("Aroused BodyMorphs: first time initialization")
	Debug.Trace("ABM: first time initialization")

	; OnInit and the MCM "Reset all state" button share the same reset path.
	; DELIBERATELY do NOT call back into the MCM from this chain. OnInit can
	; fire during MCM registration (OnConfigRegister -> Quest.Start()), and
	; calling into the MCM while SkyUI is still mid-registering creates
	; cross-script lock contention that can wedge the Papyrus VM hard enough
	; to freeze the game (reproduced in this mod's predecessor). The
	; user can click "Import Settings" from the MCM at any time afterwards.
	ResetAllState()

	Debug.Notification("Aroused BodyMorphs: initialization complete")
	debug.Trace("ABM: initialization complete")
EndEvent

Function ResetAllState()
	{Wipe persisted state back to install defaults. Called from OnInit on first install
	 AND from the MCM "Reset all state" button to recover from corrupt / upgrade-stale state
	 (None arrays, mismatched morph counts, flags stuck false, etc).

	 This explicitly overwrites toggles to their declared defaults too, since those
	 persist in the cosave and can hold arbitrary values from a previous version.
	 Re-runs the alias requirements check at the end so the SLA flags refresh
	 against the live SLA framework.}
	; Build the morph table: the full nipple / areola / vagina set.
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

	; Re-run requirements check so isNioOk / isSLAroused28 / isSLAroused29 reflect
	; the live framework state (and on first install, register the mod events + poll).
	PlayerAlias.OnPlayerLoadGame()
EndFunction

Function ResetDefaults()
	{Rebuild the MaxDefault array to match the current MorphNames set. Called from
	 OnPlayerLoadGame on every load and from ApplyMorphSet. Derives every entry from
	 DefaultForMorph so it stays correct whether the table holds the built-in set or
	 an imported custom one (unknown morphs default to 0).}
	MaxDefault = new float[128]
	Int i = 0
	While i < 128 && MorphNames[i] != ""
		MaxDefault[i] = DefaultForMorph(MorphNames[i])
		i += 1
	EndWhile
EndFunction

String[] Function FullMorphSet()
	{Ordered full morph-name list (CBBE 3BA slider names). Single source used by
	 both ApplyMorphSet (install/Reset) and EnsureFullMorphSet (non-destructive
	 upgrade) so the two never drift. The MCM groups these by area at draw time
	 (GroupForMorph), so order here only decides ordering within each group.}
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
	{(Re)build MorphNames + MaxValue (and MaxDefault via ResetDefaults) to the full
	 morph set. Every value is reset to its DefaultForMorph default, so this is a full
	 reset -- only for install / Reset. It does NOT preserve prior slider tuning; use
	 EnsureFullMorphSet for a non-destructive upgrade. These sliders show in the MCM by
	 default -- no Import needed. Morphs the body doesn't define are no-ops.}
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
	{Non-destructive upgrade: append any full-set morph not already in the table,
	 PRESERVING existing names and their tuned MaxValue. New morphs get their
	 DefaultForMorph default. No caller in 1.0 (a fresh install always holds the
	 full set) -- kept for future versions that extend FullMorphSet, so an old
	 save can gain the new sliders without wiping its tuning.}
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
	{Append morphName at slot `count` if it's not already present, returning the new
	 count. Existing entries (and their MaxValue tuning) are untouched. Bounded to the
	 128 array cap.}
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
	{Single source of per-morph default values (Natural tier -- keep in sync with
	 IntensityPresets\Natural.json). Nipple built-ins use the declared Default*
	 properties; the extended genital/labia morphs list only the preset's non-zero
	 values; any other morph (zero-valued preset entries, custom imports) defaults
	 to 0.}
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
	{Number of populated morph slots (stop at the first empty name). Used by the MCM
	 to sync its render/handler count to whatever the table actually holds.}
	Int i = 0
	While i < 128 && MorphNames[i] != ""
		i += 1
	EndWhile
	Return i
EndFunction

Int Function GroupForMorph(String morphName)
	{Area group of a morph, inferred from its name so imported custom morphs sort
	 themselves without any extra bookkeeping:
	   0 = Nipples, 1 = Areolas, 2 = Vagina, 3 = Other.
	 StringUtil.Find is case-insensitive, so any capitalisation matches. Checked
	 in priority order -- a name containing both "nipple" and "areola" would land
	 in Nipples.}
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
		Return "Nipples"
	ElseIf groupId == 1
		Return "Areolas"
	ElseIf groupId == 2
		Return "Vagina"
	EndIf
	Return "Other"
EndFunction
