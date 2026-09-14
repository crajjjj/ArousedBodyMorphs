ScriptName ABM_ConfigMenu extends SKI_ConfigBase
{The MCM for Aroused BodyMorphs.}

ABM_Quest Property MainQuest Auto
Spell Property DebugSpell Auto

float property range = 3.0 AutoReadOnly hidden

int hasReqFlag
; Like hasReqFlag but NOT set when the mod is merely switched off -- for the
; diagnostic options, which must keep working in the state they report on.
int reqOnlyFlag

int oidModEnabled
int oidDebugMode
int oidIgnoreMales
int oidPollInterval
int oidScanCellRadius
int oidIgnoreDead
int oidIgnoreMaleBeast
int oidIgnoreFemaleBeast
int oidSuppressUnderArmor
int oidUnderArmorScale

; Preset combobox entries, in fixed (subtle -> strong) order rather than
; alphabetical. Backed by the JSON files in IntensityPresets\.
String[] _intensityPresetNames

int[] oidMaxValue

string version

; Set when DebugMode changes in this menu (the toggle, or an import that flips
; it); OnConfigClose then grants or removes the power to match. Reset does its
; own removal instead, since it must not leave the menu and the Powers list
; disagreeing even briefly.
bool toggleDebugSpell = false

String Property ConfigFile = "ArousedBodyMorphs/config.json" Auto hidden
String Property MorphFile = "ArousedBodyMorphs/morph.json" Auto hidden
; MCM-side copy of the morph count, synced from MainQuest.MorphCount() on every
; menu open / morphs-page draw so the render/handler loops match the live table.
int Property MorphsShown = 23 Auto hidden

import JsonUtil
import MiscUtil


int function GetVersion()
	; Packed (M)MmmPP -- 12345 => 1.23.45. Bump alongside meta.ini; SkyUI fires
	; OnVersionUpdate when a save carries an older number.
	return 10004
endFunction

Event OnVersionUpdate(Int ver)
	{Fired by SKI_ConfigBase when the saved version is older. Updates the display
	 string ONLY: this runs during SkyUI's MCM registration with the script lock
	 contended, and reaching across to the Quest / Alias here froze the game in
	 the predecessor mod. The poll is re-registered on every load anyway.}
	int Major = ver/10000
	int Minor = (ver%10000)/100
	int Patch = ver%100
	version = Major+"."+Minor+"."+Patch
	debug.Notification("Aroused BodyMorphs: Updating to "+version)
	debug.Trace("ABM: Updating to "+version)
EndEvent

Event OnConfigInit()
	debug.Notification("Aroused BodyMorphs: Registering MCM. This could take a while.")
	debug.Trace("ABM: Registering MCM. This could take a while.")
EndEvent

event OnConfigRegister()
	debug.Notification("Aroused BodyMorphs: MCM registered!")
	debug.Trace("ABM: MCM registered!")
	SetupPages()
	oidMaxValue = new int[128]
	MainQuest.start()
endEvent


event OnConfigOpen()
	SetupPages()
	oidMaxValue = new int[128]
	; Keep the MCM-side morph count in sync with whatever the table actually holds
	; (Import and Reset both change it).
	MorphsShown = MainQuest.MorphCount()
endEvent

Function SetupPages()
	Pages = new string[2]
	Pages[0] = "$ABM_Page_General"
	Pages[1] = "$ABM_Page_Morphs"
EndFunction

Function RefreshReqFlag()
	{Recompute the disabled-flag for the tuning options: set when the mod is off
	 or its requirements aren't met, since nothing they control would have effect.

	 Must run on EVERY page draw, not once per open: the master toggle and Reset
	 both change it mid-menu and redraw. A flag cached at open time would leave
	 options greyed against freshly-drawn "OK" rows -- failing the very recovery
	 path Reset exists for.

	 NOT applied to "Mod enabled", Import / Export / Reset (they must stay usable
	 to get back out of the disabled state) nor to the diagnostics, which take
	 reqOnlyFlag -- a switched-off mod is a thing you may want to diagnose.}
	reqOnlyFlag = 0
	If !(MainQuest.isNioOk && (MainQuest.isSLAroused28 || MainQuest.isSLAroused29))
		reqOnlyFlag = OPTION_FLAG_DISABLED
	EndIf
	hasReqFlag = reqOnlyFlag
	If !MainQuest.ModEnabled
		hasReqFlag = OPTION_FLAG_DISABLED
	EndIf
EndFunction

Event OnConfigClose()
	; Mirror whatever changed this session into the optional native DLL (single
	; push here instead of one per option handler). No-op without the DLL.
	MainQuest.PlayerAlias.PushConfigToNative()

	; Re-apply the player's morphs now. Every value edit in this menu (intensity
	; preset, a MaxValue slider, the under-armor scale) only writes to the quest's
	; tables -- nothing applies them -- so without this the body keeps the old
	; look until the next update tick: up to 5s on the default poll, up to 120s
	; with polling set to 0, and in native + OSL Aroused mode until OSL happens to
	; fire an arousal event, since that backend runs no poll at all. Long enough
	; to read as "the preset did nothing".
	;
	; Cost is one refresh per menu close, which is exactly the moment the user is
	; waiting to see the result. When nothing actually changed, SetActorMorphs'
	; probe finds the values already applied and skips the writes + mesh rebuild.
	; NPCs are deliberately not swept here: that is a full cell scan for a change
	; the user is judging on their own body, and they catch up on the next
	; heartbeat anyway.
	MainQuest.PlayerAlias.RefreshPlayer()

	if toggleDebugSpell
		Actor pc = MainQuest.PlayerAlias.GetPlayerRef()
		if MainQuest.DebugMode
			pc.addSpell(DebugSpell)
		else
			pc.removeSpell(DebugSpell)
		endIf
		toggleDebugSpell = false
	endIf
EndEvent

event OnPageReset(string page)
	;;NOTE TO SELF;;;;;;;;;;;;
	;oid = AddSliderOption("desc",val,"{0}",flag)
	;oid = AddToggleOption("desc",val,flag)
	;oid = AddTextOption("desc","val",flag)
	;;;;;;;;;;;;;;;;;;;;;;;;;;
	RefreshReqFlag()
	ClearOptionIDs()
	If page == Pages[1]
		DrawMorphsPage()
	Else
		; "General", and the no-page-selected state ("") right after opening.
		DrawGeneralPage()
	EndIf
endEvent

Function ClearOptionIDs()
	{Wipe every oid before a page draw. SkyUI ids are buffer indices from 0, so a
	 stale oid from the OTHER page can collide with a fresh one here and misroute
	 the handler -- e.g. a morph slider opening the poll-interval dialog.}
	oidModEnabled         = -1
	oidDebugMode          = -1
	oidIgnoreMales        = -1
	oidPollInterval       = -1
	oidScanCellRadius     = -1
	oidIgnoreDead         = -1
	oidIgnoreMaleBeast    = -1
	oidIgnoreFemaleBeast  = -1
	oidSuppressUnderArmor = -1
	oidUnderArmorScale    = -1
	int i = 0
	while i < 128
		oidMaxValue[i] = -1
		i += 1
	endWhile
EndFunction

; Display strings are "$ABM_*" keys resolved from
; Interface\Translations\ArousedBodyMorphs_<LANGUAGE>.txt (the file stem is the
; PLUGIN name, not the MCM's ModName). SkyUI only substitutes when the WHOLE
; string matches a key -- "$ABM_Foo bar" is left verbatim -- so the handful of
; strings below that concatenate a live value (title + version, the morph count,
; the applied-arousal readout) are deliberately left in English rather than
; rendered as a broken half-translated label.
Function DrawGeneralPage()
	SetCursorFillMode(TOP_TO_BOTTOM)

	;Left side
	SetCursorPosition(0)
	AddHeaderOption("Aroused BodyMorphs " + version)
	; Master switch. Never carries hasReqFlag -- it's the way back out of the
	; disabled state, so it has to stay clickable.
	oidModEnabled = AddToggleOption("$ABM_Opt_ModEnabled", MainQuest.ModEnabled)

	AddHeaderOption("$ABM_Hdr_Requirements")
	; Plain (disabled) status text, not clickable toggles -- these are read-only.
	String nioLabel = "$ABM_Val_Missing"
	If MainQuest.isNioOk
		nioLabel = "$ABM_Val_OK"
	EndIf
	AddTextOption("$ABM_Opt_NiOverride", nioLabel, OPTION_FLAG_DISABLED)
	String slaLabel = "$ABM_Val_MissingTryLoad"
	If MainQuest.isSLAroused29
		slaLabel = "$ABM_Val_SlaNG"
	ElseIf MainQuest.isSLAroused28
		slaLabel = "$ABM_Val_SlaLegacy"
	EndIf
	AddTextOption("$ABM_Opt_SexLabAroused", slaLabel, OPTION_FLAG_DISABLED)
	; Optional native layer status. Without the DLL the row says so and the
	; Papyrus pipeline (this file's siblings) does all the work.
	String nativeLabel = "$ABM_Backend_None"
	If ABM_Native.IsInstalled()
		nativeLabel = ABM_Native.GetBackendName()
	EndIf
	AddTextOption("$ABM_Opt_NativeEngine", nativeLabel, OPTION_FLAG_DISABLED)
	; Live sanity check: click to read arousal fresh from SLA and re-apply morphs
	; (PokePlayerArousal on the alias).
	AddTextOptionST("State_CheckPlayer", "$ABM_Opt_PlayerArousal", "$ABM_Val_CheckNow", reqOnlyFlag)

	AddHeaderOption("$ABM_Hdr_IntensityPreset")
	; Selecting a preset overwrites every MaxValue slider it has a key for;
	; morphs the preset doesn't cover (custom imports) keep their values.
	String presetLabel = MainQuest.IntensityPreset
	If presetLabel == ""
		presetLabel = "$ABM_Val_Choose"
	EndIf
	AddMenuOptionST("State_IntensityPreset", "$ABM_Opt_Preset", presetLabel, hasReqFlag)

	AddHeaderOption("$ABM_Hdr_UnderArmor")
	oidSuppressUnderArmor = AddToggleOption("$ABM_Opt_SuppressUnderArmor", MainQuest.SuppressUnderArmor, hasReqFlag)
	; Slider stays visible but disabled while suppression is off, so its role is clear.
	int uaFlag = hasReqFlag
	if !MainQuest.SuppressUnderArmor
		uaFlag = OPTION_FLAG_DISABLED
	endif
	oidUnderArmorScale = AddSliderOption("$ABM_Opt_NippleSizeUnderArmor", MainQuest.UnderArmorScale, "{2}", uaFlag)

	AddHeaderOption("$ABM_Hdr_Performance")
	oidPollInterval   = AddSliderOption("$ABM_Opt_PollInterval", MainQuest.PollInterval, "{1}", hasReqFlag)
	oidScanCellRadius = AddSliderOption("$ABM_Opt_ScanRadius",  MainQuest.ScanCellRadius, "{0}", hasReqFlag)

	;Right side
	SetCursorPosition(1)
	AddHeaderOption("$ABM_Hdr_ActorFilters")
	oidIgnoreMales       = AddToggleOption("$ABM_Opt_IgnoreMales",         MainQuest.IgnoreMales)
	oidIgnoreDead        = AddToggleOption("$ABM_Opt_IgnoreDead",          MainQuest.IgnoreDead)
	oidIgnoreMaleBeast   = AddToggleOption("$ABM_Opt_IgnoreMaleBeasts",   MainQuest.IgnoreMaleBeast)
	oidIgnoreFemaleBeast = AddToggleOption("$ABM_Opt_IgnoreFemaleBeasts", MainQuest.IgnoreFemaleBeast)

	AddHeaderOption("$ABM_Hdr_Debug")
	; Not gated: its traces and the debug spell are exactly what you want when the
	; requirements check is failing or the mod has been switched off.
	oidDebugMode = AddToggleOption("$ABM_Opt_DebugMode", MainQuest.DebugMode)

	AddHeaderOption("$ABM_Hdr_ImportExport")
	; Deliberately never disabled: they only move JSON <-> quest properties, and
	; staying usable when the requirements check fails is part of the recovery
	; story (same reasoning as the Reset button below).
	AddTextOptionST("State_Import", "$ABM_Opt_ImportSettings", "$ABM_Val_Import", 0)
	AddTextOptionST("State_Export", "$ABM_Opt_ExportSettings", "$ABM_Val_Export", 0)

	AddHeaderOption("$ABM_Hdr_Recovery")
	; Reset stays enabled even when NiOverride is missing -- the whole point
	; of this button is to recover from a state where things aren't right.
	AddTextOptionST("State_Reset", "$ABM_Opt_ResetAllState", "$ABM_Val_Reset", 0)
EndFunction

Function DrawMorphsPage()
	; Sync the render/handler count to the live morph table (Import and Reset
	; both change it) before drawing sliders.
	MorphsShown = MainQuest.MorphCount()
	SetCursorFillMode(TOP_TO_BOTTOM)

	;Left side
	SetCursorPosition(0)
	AddHeaderOption("Morphs (" + MorphsShown + ")")
	AddTextOption("$ABM_Note_Inverted1", "", OPTION_FLAG_DISABLED)
	AddTextOption("$ABM_Note_Inverted2", "", OPTION_FLAG_DISABLED)

	; Display order: grouped by area, table order preserved within a group.
	; order[d] maps display position -> table index, so the handlers keep
	; indexing oidMaxValue by table index.
	int[] order = new int[128]
	int total = 0
	int headers = 0
	int g = 0
	while g < 4
		bool groupHasAny = false
		int i = 0
		while i < MorphsShown
			if MainQuest.GroupForMorph(MainQuest.MorphNames[i]) == g
				order[total] = i
				total += 1
				groupHasAny = true
			endif
			i += 1
		endwhile
		if groupHasAny
			headers += 1
		endif
		g += 1
	endwhile

	; SkyUI renders ~26 rows per column without scrolling, so the full set must
	; break at the midpoint. The break can land mid-group; headers don't repeat.
	int split = (total + headers + 3 + 1) / 2
	int rows = 3
	int column = 0
	int lastGroup = -1
	int d = 0
	while d < total
		int idx = order[d]
		int grp = MainQuest.GroupForMorph(MainQuest.MorphNames[idx])
		if grp != lastGroup
			; +1: never leave a group header as the last row of the left column
			; with all its sliders on the right.
			if column == 0 && rows + 1 >= split
				SetCursorPosition(1)
				column = 1
			endif
			AddHeaderOption(MainQuest.GroupName(grp))
			rows += 1
			lastGroup = grp
		elseif column == 0 && rows >= split
			SetCursorPosition(1)
			column = 1
		endif
		oidMaxValue[idx] = AddSliderOption(MainQuest.MorphNames[idx], MainQuest.MaxValue[idx], "{2}", hasReqFlag)
		rows += 1
		d += 1
	endwhile
EndFunction

state State_CheckPlayer
	event OnHighlightST()
		SetInfoText("$ABM_Info_CheckPlayer")
	endevent
	event OnSelectST()
		SetTextOptionValueST("...")
		int arousal = MainQuest.PlayerAlias.PokePlayerArousal()
		If arousal == -1
			SetTextOptionValueST("$ABM_Val_SlaUnavailable")
		ElseIf arousal == -3
			; Master switch is off -- the mod writes nothing by design.
			SetTextOptionValueST("$ABM_Val_ModDisabled")
		ElseIf arousal == -2
			; The actor filters (Ignore males / dead / beasts) excluded the player, so
			; UpdateActor wrote nothing -- reporting a number here would be a false pass.
			SetTextOptionValueST("$ABM_Val_SkippedByFilters")
		Else
			SetTextOptionValueST(arousal + " (applied)")
		EndIf
	endevent
endstate

state State_Import
	event OnHighlightST()
		SetInfoText("$ABM_Info_Import")
	endevent
	event OnSelectST()
		ImportUserSettings()
		SetTextOptionValueST("$ABM_Val_Loading")
		ForcePageReset()
	endevent
endstate

state State_Export
	event OnHighlightST()
		SetInfoText("$ABM_Info_Export")
	endevent
	event OnSelectST()
		ExportUserSettings()
		SetTextOptionValueST("$ABM_Val_Loading")
		ForcePageReset()
	endevent
endstate

state State_Reset
	event OnHighlightST()
		SetInfoText("$ABM_Info_Reset")
	endevent
	event OnSelectST()
		MainQuest.ResetAllState()
		; Drop the debug power here, now. ResetAllState forces DebugMode off but
		; cannot remove the power itself: it also runs from Quest.OnInit, where
		; calling back into this menu mid-registration froze the game in the
		; predecessor mod. That constraint is on the QUEST, though -- we ARE the
		; menu, and we own the spell property, so the reset button can just do it
		; rather than leave the toggle and the Powers list disagreeing until the
		; next menu close. (OnInit's own reset never needs this: nothing was ever
		; granted on a first install.)
		Actor pc = MainQuest.PlayerAlias.GetPlayerRef()
		If pc
			pc.RemoveSpell(DebugSpell)
		EndIf
		toggleDebugSpell = false
		; Sync the MCM-side morph count to the rebuilt table (persisted separately
		; from the quest's MorphNames array, which the quest reset doesn't see).
		MorphsShown = MainQuest.MorphCount()
		SetTextOptionValueST("$ABM_Val_Done")
		ForcePageReset()
	endevent
endstate

state State_IntensityPreset
	event OnMenuOpenST()
		String[] names = GetIntensityPresetNames()
		SetMenuDialogOptions(names)
		; Highlight the currently-selected preset in the dropdown (if any).
		int si = 0
		int i = 0
		String current = MainQuest.IntensityPreset
		While i < names.Length
			If names[i] == current
				si = i
			EndIf
			i += 1
		EndWhile
		SetMenuDialogStartIndex(si)
	endevent
	event OnMenuAcceptST(int index)
		String[] names = GetIntensityPresetNames()
		If index < 0 || index >= names.Length
			return
		EndIf
		SetMenuOptionValueST("$ABM_Val_Loading")
		String preset = names[index]
		ApplyIntensityPreset(preset)
		MainQuest.IntensityPreset = preset
		SetMenuOptionValueST(preset)
		; Redraw so the Morphs page picks up the new MaxValue on its next draw.
		ForcePageReset()
	endevent
	event OnHighlightST()
		SetInfoText("$ABM_Info_Preset")
	endevent
endstate

event OnOptionSelect(int option)
	if option == oidModEnabled
		; SetModEnabled owns the whole transition and writes the property itself,
		; so read it back. The redraw greys the other options to match.
		MainQuest.PlayerAlias.SetModEnabled(!MainQuest.ModEnabled)
		SetToggleOptionValue(option, MainQuest.ModEnabled)
		ForcePageReset()
		return
	elseif option == oidDebugMode
		MainQuest.DebugMode = !MainQuest.DebugMode
		SetToggleOptionValue(option,MainQuest.DebugMode)
		toggleDebugSpell = true
		return
	elseif option == oidIgnoreMales
		MainQuest.IgnoreMales = !MainQuest.IgnoreMales
		SetToggleOptionValue(option,MainQuest.IgnoreMales)
		return
	elseif option == oidIgnoreDead
		MainQuest.IgnoreDead = !MainQuest.IgnoreDead
		SetToggleOptionValue(option,MainQuest.IgnoreDead)
		return
	elseif option == oidIgnoreMaleBeast
		MainQuest.IgnoreMaleBeast = !MainQuest.IgnoreMaleBeast
		SetToggleOptionValue(option,MainQuest.IgnoreMaleBeast)
		return
	elseif option == oidIgnoreFemaleBeast
		MainQuest.IgnoreFemaleBeast = !MainQuest.IgnoreFemaleBeast
		SetToggleOptionValue(option,MainQuest.IgnoreFemaleBeast)
		return
	elseif option == oidSuppressUnderArmor
		MainQuest.SuppressUnderArmor = !MainQuest.SuppressUnderArmor
		SetToggleOptionValue(option,MainQuest.SuppressUnderArmor)
		; Redraw so the "Nipple size under armor" slider enables/disables to match.
		ForcePageReset()
		return
	endif
endEvent


event OnOptionDefault(int option)
	if option == oidModEnabled
		MainQuest.PlayerAlias.SetModEnabled(true)
		SetToggleOptionValue(option,true)
		ForcePageReset()
		return
	Elseif option == oidDebugMode
		MainQuest.DebugMode = false
		SetToggleOptionValue(option,false)
		toggleDebugSpell = true
		return
	Elseif option == oidIgnoreMales
		MainQuest.IgnoreMales = true
		SetToggleOptionValue(option,true)
		return
	Elseif option == oidIgnoreDead
		MainQuest.IgnoreDead = true
		SetToggleOptionValue(option,true)
		return
	Elseif option == oidIgnoreMaleBeast
		MainQuest.IgnoreMaleBeast = true
		SetToggleOptionValue(option,true)
		return
	Elseif option == oidIgnoreFemaleBeast
		MainQuest.IgnoreFemaleBeast = true
		SetToggleOptionValue(option,true)
		return
	Elseif option == oidPollInterval
		MainQuest.PollInterval = MainQuest.DefaultPollInterval
		SetSliderOptionValue(option, MainQuest.PollInterval, "{1}")
		MainQuest.PlayerAlias.RestartPolling()
		return
	Elseif option == oidScanCellRadius
		MainQuest.ScanCellRadius = MainQuest.DefaultScanCellRadius
		SetSliderOptionValue(option, MainQuest.ScanCellRadius, "{0}")
		return
	Elseif option == oidSuppressUnderArmor
		MainQuest.SuppressUnderArmor = true
		SetToggleOptionValue(option,true)
		ForcePageReset()
		return
	Elseif option == oidUnderArmorScale
		MainQuest.UnderArmorScale = MainQuest.DefaultUnderArmorScale
		SetSliderOptionValue(option, MainQuest.UnderArmorScale, "{2}")
		return
	Else
		int i = 0
		while i < MorphsShown
			If option == oidMaxValue[i]
				MainQuest.MaxValue[i] = MainQuest.MaxDefault[i]
				SetSliderOptionValue(option, MainQuest.MaxValue[i], "{2}")
				return
			Endif
			i += 1
		endWhile
	endIf
endEvent

Event OnOptionSliderOpen(Int option)
	If option == oidPollInterval
		SetSliderDialogRange(0.0, 60.0)
		SetSliderDialogInterval(0.5)
		SetSliderDialogStartValue(MainQuest.PollInterval)
		SetSliderDialogDefaultValue(MainQuest.DefaultPollInterval)
		return
	ElseIf option == oidScanCellRadius
		; Starts at 0 = NPC updates off; the 100 interval keeps 0 reachable.
		SetSliderDialogRange(0.0, 10000.0)
		SetSliderDialogInterval(100.0)
		SetSliderDialogStartValue(MainQuest.ScanCellRadius)
		SetSliderDialogDefaultValue(MainQuest.DefaultScanCellRadius)
		return
	ElseIf option == oidUnderArmorScale
		; Allow negatives: NippleSize is an inverted morph, so a negative scale
		; pushes the nipples smaller than baseline (an active tuck under armor),
		; not just toward neutral.
		SetSliderDialogRange(-1.0, 1.0)
		SetSliderDialogInterval(0.05)
		SetSliderDialogStartValue(MainQuest.UnderArmorScale)
		SetSliderDialogDefaultValue(MainQuest.DefaultUnderArmorScale)
		return
	EndIf

	SetSliderDialogRange(-range, range)
	SetSliderDialogInterval(0.01)

	int i = 0
	while i < MorphsShown
		If option == oidMaxValue[i]
			SetSliderDialogStartValue(MainQuest.MaxValue[i])
			SetSliderDialogDefaultValue(MainQuest.MaxDefault[i])
			return
		Endif
		i += 1
	endWhile


EndEvent

Event OnOptionSliderAccept(Int option, Float value)
	If option == oidPollInterval
		MainQuest.PollInterval = value
		SetSliderOptionValue(option, MainQuest.PollInterval, "{1}")
		MainQuest.PlayerAlias.RestartPolling()
		return
	ElseIf option == oidScanCellRadius
		Float oldRadius = MainQuest.ScanCellRadius
		MainQuest.ScanCellRadius = value
		SetSliderOptionValue(option, MainQuest.ScanCellRadius, "{0}")
		; Turning NPCs off: sweep at the OLD radius first, or everyone already
		; morphed freezes at their last values with nothing left to update them.
		If value <= 0.0 && oldRadius > 0.0
			; Push BEFORE clearing, exactly as SetModEnabled does. The DLL's
			; heartbeat sink gates on the radius it was last given, and the
			; normal push only happens on MCM close -- so without this, a
			; sla_UpdateComplete landing while the menu is still open would
			; re-morph everyone we just cleared, and the later push of 0 would
			; then strand them there permanently.
			MainQuest.PlayerAlias.PushConfigToNative()
			MainQuest.PlayerAlias.ClearNearbyMorphsAt(oldRadius)
		EndIf
		return
	ElseIf option == oidUnderArmorScale
		MainQuest.UnderArmorScale = value
		SetSliderOptionValue(option, MainQuest.UnderArmorScale, "{2}")
		return
	EndIf

	int i = 0
	while i < MorphsShown
		If option == oidMaxValue[i]
			MainQuest.MaxValue[i] = value
			SetSliderOptionValue(option, MainQuest.MaxValue[i], "{2}")
			return
		Endif
		i += 1
	endWhile

EndEvent

Event OnOptionHighlight(Int option)
	If option == oidModEnabled
		SetInfoText("$ABM_Info_ModEnabled")
	ElseIf option == oidDebugMode
		SetInfoText("$ABM_Info_DebugMode")
	ElseIf option == oidIgnoreMales
		SetInfoText("$ABM_Info_IgnoreMales")
	ElseIf option == oidIgnoreDead
		SetInfoText("$ABM_Info_IgnoreDead")
	ElseIf option == oidIgnoreMaleBeast
		SetInfoText("$ABM_Info_IgnoreMaleBeasts")
	ElseIf option == oidIgnoreFemaleBeast
		SetInfoText("$ABM_Info_IgnoreFemaleBeasts")
	ElseIf option == oidPollInterval
		SetInfoText("$ABM_Info_PollInterval")
	ElseIf option == oidScanCellRadius
		SetInfoText("$ABM_Info_ScanRadius")
	ElseIf option == oidSuppressUnderArmor
		SetInfoText("$ABM_Info_SuppressUnderArmor")
	ElseIf option == oidUnderArmorScale
		SetInfoText("$ABM_Info_UnderArmorScale")
	Else
		int i = 0
		while i < MorphsShown
			If option == oidMaxValue[i]
				SetInfoText("$ABM_Info_MorphSlider")
				return
			Endif
			i += 1
		endWhile

		;Default:
		SetInfoText("$ABM_Info_Default")
	EndIf
EndEvent

Bool Function ImportUserSettings()
	; General settings
	; data/SKSE/Plugins/StorageUtilData/ArousedBodyMorphs/config.json
	bool oldDebugMode = MainQuest.DebugMode
	bool oldModEnabled = MainQuest.ModEnabled
	Load(ConfigFile)
	; Missing-key defaults match the quest's declared property defaults, so a
	; partial / older config.json hydrates into install defaults, not zero/false.
	MainQuest.ModEnabled        = (GetStringValue(ConfigFile, "modenabled",        "1") as int) as bool
	MainQuest.DebugMode         = (GetStringValue(ConfigFile, "debugmode",         "0") as int) as bool
	MainQuest.IgnoreMales       = (GetStringValue(ConfigFile, "ignoremales",       "1") as int) as bool
	MainQuest.IgnoreDead        = (GetStringValue(ConfigFile, "ignoredead",        "1") as int) as bool
	MainQuest.IgnoreMaleBeast   = (GetStringValue(ConfigFile, "ignoremalebeast",   "1") as int) as bool
	MainQuest.IgnoreFemaleBeast = (GetStringValue(ConfigFile, "ignorefemalebeast", "1") as int) as bool
	MainQuest.ScanCellRadius    = GetStringValue(ConfigFile, "scancellradius", "1000") as float
	; Clamp to the MCM's own range. A hand-edited or unparseable value casts to
	; 0.0, which is a real setting now (NPCs off) rather than the old footgun
	; where PapyrusUtil read it as "scan the entire cell".
	If MainQuest.ScanCellRadius < 0.0 || MainQuest.ScanCellRadius > 10000.0
		MainQuest.ScanCellRadius = MainQuest.DefaultScanCellRadius
	EndIf
	MainQuest.PollInterval      = GetStringValue(ConfigFile, "pollinterval",   "5")    as float
	; "Natural" as the missing-default: the built-in slider defaults ARE the
	; Natural tier, so a config.json without this key still reports honestly.
	MainQuest.IntensityPreset   = GetStringValue(ConfigFile, "intensitypreset", "Natural")
	MainQuest.SuppressUnderArmor = (GetStringValue(ConfigFile, "suppressunderarmor", "1") as int) as bool
	MainQuest.UnderArmorScale    = GetStringValue(ConfigFile, "underarmorscale", "0") as float
	UnLoad(ConfigFile, false, false)

	; An imported DebugMode change must grant/remove the debug spell on menu
	; close, same as toggling it by hand.
	If MainQuest.DebugMode != oldDebugMode
		toggleDebugSpell = true
	EndIf
	; Sliders
	; data/SKSE/Plugins/StorageUtilData/ArousedBodyMorphs/morph.json
	Load(MorphFile)
	int it = StringListCount(MorphFile, "morphs")
	if it > 0
		; Only overwrite the morph table if the file actually contains entries;
		; otherwise the defaults set by ABM_Quest.OnInit() are preserved on first install.
		; Realloc BOTH arrays together so MaxValue can't retain stale entries past the new count.
		MainQuest.MorphNames = new String[128]
		MainQuest.MaxValue   = new Float[128]
		int i = 0
		int in = 0
		while i < it && i < 128
			string MorphName = StringListGet(MorphFile, "morphs", i)
			if MorphName != ""
				MainQuest.MorphNames[in] = MorphName
				MainQuest.MaxValue[in] = GetStringValue(MorphFile, MorphName, "0") as float
				in += 1
			endif
			i += 1
		EndWhile
		MorphsShown = in
		; Rebuild MaxDefault against the imported names NOW, not on the next game
		; load -- otherwise the R-key slider default serves values from the old table.
		MainQuest.ResetDefaults()
	endif
	UnLoad(MorphFile, false, false)

	; Deliberately last, after the morph table has landed: an imported flip of the
	; master switch runs the full transition, and re-applying before the sliders
	; were read would paint the pre-import values -- and leave them there if the
	; imported poll interval is 0.
	If MainQuest.ModEnabled != oldModEnabled
		MainQuest.PlayerAlias.SetModEnabled(MainQuest.ModEnabled)
	Else
		; Re-arm the poll at the imported interval (also handles 0 <-> non-zero).
		MainQuest.PlayerAlias.RestartPolling()
	EndIf
	return TRUE
EndFunction

String[] Function GetIntensityPresetNames()
	{Lazy-allocate the preset list, ordered subtle -> strong to match the four
	 shipped JSON files. Extra JSON files in that folder won't appear -- the list
	 is fixed.}
	If !_intensityPresetNames
		_intensityPresetNames = new String[4]
		_intensityPresetNames[0] = "Minimal"
		_intensityPresetNames[1] = "Natural"
		_intensityPresetNames[2] = "Noticeable"
		_intensityPresetNames[3] = "Exaggerated"
	EndIf
	Return _intensityPresetNames
EndFunction

Function ApplyIntensityPreset(String presetName)
	{Overwrite MaxValue[i] for every morph the preset has a key for. Morphs it
	 doesn't cover keep their value, so custom imports aren't zeroed. Preset keys
	 are exactly the FullMorphSet names -- no normalisation needed.}
	String path = "ArousedBodyMorphs/IntensityPresets/" + presetName
	Load(path)
	int i = 0
	String[] morphNames = MainQuest.MorphNames
	while i < 128 && morphNames[i] != ""
		String value = GetStringValue(path, morphNames[i], "")
		If value != ""
			MainQuest.MaxValue[i] = value as float
		EndIf
		i += 1
	EndWhile
	UnLoad(path, false, false)
EndFunction

Bool Function ExportUserSettings()
	Load(ConfigFile)
	Load(MorphFile)
	; General settings
	SetStringValue(ConfigFile, "modenabled",        (MainQuest.ModEnabled        as int) as string)
	SetStringValue(ConfigFile, "debugmode",         (MainQuest.DebugMode         as int) as string)
	SetStringValue(ConfigFile, "ignoremales",       (MainQuest.IgnoreMales       as int) as string)
	SetStringValue(ConfigFile, "ignoredead",        (MainQuest.IgnoreDead        as int) as string)
	SetStringValue(ConfigFile, "ignoremalebeast",   (MainQuest.IgnoreMaleBeast   as int) as string)
	SetStringValue(ConfigFile, "ignorefemalebeast", (MainQuest.IgnoreFemaleBeast as int) as string)
	SetStringValue(ConfigFile, "scancellradius",     MainQuest.ScanCellRadius              as string)
	SetStringValue(ConfigFile, "pollinterval",       MainQuest.PollInterval                as string)
	SetStringValue(ConfigFile, "intensitypreset",    MainQuest.IntensityPreset)
	SetStringValue(ConfigFile, "suppressunderarmor", (MainQuest.SuppressUnderArmor as int) as string)
	SetStringValue(ConfigFile, "underarmorscale",     MainQuest.UnderArmorScale            as string)
	; Clear any previously-exported list so we don't accumulate duplicates across exports.
	StringListClear(MorphFile, "morphs")
	; Sliders
	int i = 0
	while i < MorphsShown
		if MainQuest.MorphNames[i] != ""
			StringListAdd(MorphFile, "morphs", (MainQuest.MorphNames[i]), false)
			SetStringValue(MorphFile, MainQuest.MorphNames[i], (MainQuest.MaxValue[i] As string))
		endif
		i += 1
	EndWhile
	UnLoad(ConfigFile, true, false)
	UnLoad(MorphFile, true, false)
	return TRUE
EndFunction
