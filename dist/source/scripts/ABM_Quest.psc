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
; nipples don't clip. "Covered" = a cuirass / body-clothing keyword on ANY worn
; item -- tops sit on slots 46 and 56 as often as on 32 -- unless Advanced
; Nudity Detection flags the actor Nude / Topless / Showing Breasts, which is
; what demotes a keyworded accessory back to bare. See IsTopCovered.
; The player refreshes on equip/unequip; NPCs on the next heartbeat.
bool Property SuppressUnderArmor = true Auto Hidden

; Multiplier applied while covered: 0.0 = fully flat (no clipping), 1.0 = no
; reduction.
float Property UnderArmorScale = 0.0 Auto Hidden
float Property DefaultUnderArmorScale = 0.0 AutoReadOnly Hidden

; WHICH morphs UnderArmorScale reaches is data, not an MCM option: suppress.json
; holds one list whose entries are either an exact morph name or an area keyword
; (nipples / areolas / vagina / breasts / butt / other, matched via
; GroupForMorph, which is the one-liner for a body whose sliders aren't
; listed). SHIPS as the nipple + areola slider names of 3BA, UBE and BHUNP --
; nothing below the chest, since "covered" is a CHEST test and says nothing
; about a vagina or butt slider, which a skimpy armor leaves on show anyway.
; The breast swell is deliberately NOT on the list either: it stays under a
; top (add "breasts" to the file to flatten it there). A body outside that
; list therefore gets no suppression until its names (or a keyword) are added:
; that is the cost of an explicit list, and the readme says so. Edit the file
; to widen or narrow it; the MCM toggle stays a plain on/off.
String Property SuppressFile = "ArousedBodyMorphs/suppress.json" AutoReadOnly Hidden

string[] Property MorphNames Auto Hidden
float[] Property MaxValue Auto Hidden
float[] Property MaxDefault Auto Hidden

; 1 per MorphNames slot the under-armor scale applies to, 0 otherwise -- the
; resolved suppress.json, cached so the writer only indexes an array and the
; file is never read per morph. Int rather than Bool because it is pushed to the
; DLL verbatim. Rebuilt by RebuildMorphTables (table change + every game load,
; which is what makes a hand-edited file take effect).
int[] Property MorphSuppressed Auto Hidden
bool Property AnyMorphSuppressed = false Auto Hidden

; Which body table each MorphNames slot belongs to: BODY_MAIN (the body this
; game was built for -- CBBE 3BA out of the box, or whatever a body patch
; imported) or BODY_UBE. ONE array of slots holds both tables, so a slider name
; can sit in it twice with a value per body (NippleLength does), and an actor
; only ever gets the slots of its own body -- see BodyOf.
; PRIMARY state, not derived: a name alone cannot say which table it is in.
int[] Property MorphBody Auto Hidden
int Property BODY_MAIN = 0 AutoReadOnly Hidden
int Property BODY_UBE  = 1 AutoReadOnly Hidden

; Layout version of the table above. 0 on a save from before 1.2.0, which held
; one body and no MorphBody; EnsureBodyTables upgrades those once, on load.
int Property TableVersion = 0 Auto Hidden
int Property CurrentTableVersion = 2 AutoReadOnly Hidden

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
	{First-time setup; runs once, when the ENGINE starts this quest -- it is
	 Start Game Enabled in the ESP, so the mod comes up on a new game (and on a
	 mid-playthrough install) without SkyUI being involved at all. The MCM keeps
	 a Start() call only as a recovery line for old saves; see there.

	 Deliberately SHORT, and it must stay that way. It still lands in the busiest
	 moment of a game start, alongside SkyUI registering every installed MCM, so
	 work done here competes with that: a long chain is how a menu ends up
	 lagging, or never registering at all. So OnInit only builds this script's
	 own state, and everything that reaches OUTSIDE it -- the framework lookup,
	 the NiOverride probe, the AND form resolves, mod-event registration, the
	 poll, the native push -- waits for OnUpdate one second later. It also never
	 calls back into the MCM: that cross-script lock contention froze the game in
	 the predecessor mod.}
	Debug.Trace("ABM: first time initialization")
	ResetStoredState()
	RegisterForSingleUpdate(1.0)
EndEvent

Event OnUpdate()
	{The deferred half of OnInit, running once SkyUI's registration pass is done.
	 Only ever armed by OnInit -- nothing else in this script uses the update
	 slot.}
	Debug.Trace("ABM: running deferred first-time setup")
	PlayerAlias.OnPlayerLoadGame()
	Debug.Notification("Aroused BodyMorphs: initialization complete")
	Debug.Trace("ABM: initialization complete")
EndEvent

Function ResetAllState()
	{Wipe persisted state back to install defaults AND re-run the requirement
	 check. The MCM's "Reset all state" entry point, for recovering from corrupt
	 / upgrade-stale state (None arrays, mismatched counts, flags stuck false).

	 Synchronous on purpose: the user is watching the menu and expects the
	 Requirements rows to be right when it redraws. OnInit takes the split path
	 instead -- see there.}
	ResetStoredState()

	; Refresh the requirement flags against the live framework, and on first
	; install register the mod events + poll.
	PlayerAlias.OnPlayerLoadGame()
EndFunction

Function ResetStoredState()
	{The data half of a reset: this script's own tables and toggles, with no
	 reach outside it beyond the suppress.json read. Split from ResetAllState so
	 OnInit can run it inside SkyUI's registration pass and defer the rest.

	 Toggles are overwritten too, since the cosave can hold arbitrary values
	 from an older version.}
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
EndFunction

Function ResetDefaults()
	{Rebuild everything derived from MorphNames -- MaxDefault (from
	 DefaultForMorph, so it stays right for imported tables too: unknown -> 0)
	 and the per-slot flags. All of it lives here rather than in separate calls
	 so no path can refresh one and leave another stale. A table from before
	 1.2.0 is brought up to the per-body layout first; see EnsureBodyTables.}
	MaxDefault = new float[128]
	If !MorphNames
		; Corrupt / not-yet-built table (the state "Reset all state" exists to
		; recover from). Indexing it would throw, and this runs on the load path
		; now, so it would take the rest of OnPlayerLoadGame -- requirements, SLA
		; flavor, the poll -- down with it. RebuildMorphTables bails on the same
		; condition after allocating, so the flags array still ends up valid.
		RebuildMorphTables()
		return
	EndIf
	EnsureBodyTables()
	Int i = 0
	While i < 128 && MorphNames[i] != ""
		MaxDefault[i] = DefaultForMorph(MorphNames[i], MorphBody[i])
		i += 1
	EndWhile
	RebuildMorphTables()
EndFunction

Function EnsureBodyTables()
	{One-time upgrade of a table saved (or imported from a file written) before
	 1.2.0, which held a single body and had no MorphBody. Keyed on
	 TableVersion, so it is one compare on every later load.

	 Lives on the load path, NOT in the MCM's OnVersionUpdate: that event fires
	 inside SkyUI's registration pass, and reaching across to this script from
	 there froze the game in the predecessor mod.

	 Non-destructive -- every existing slot keeps its tuned value, and only its
	 body tag is decided here:
	 - A slot goes to the UBE table when its name is one only UBE has. The three
	   names UBE shares with another body (NippleLength with 3BA and BHUNP,
	   ClitorisErection and PussyCute with BHUNP) say nothing on their own, so
	   they stay on the main table...
	 - ...unless the WHOLE table is UBE names, which is the old UBE body patch
	   imported as-is: then every slot is UBE's, and the main table, left empty,
	   gets the built-in set at its defaults.
	 Whatever the UBE table still lacks is then appended at UBE's defaults, and
	 the swell entries arrive at 0 on both, so nothing changes on screen for a
	 body that was already set up.}
	If TableVersion >= CurrentTableVersion
		return
	EndIf
	If !MorphNames
		; Corrupt table. "Reset all state" rebuilds it at the current version.
		return
	EndIf
	MorphBody = new int[128]
	String[] ubeSet = UbeMorphSet()
	Int count = MorphCount()

	Bool anyUbeOnly = false
	Bool anyOther = false
	Int i = 0
	While i < count
		If IsUbeOnlyName(MorphNames[i], ubeSet)
			anyUbeOnly = true
		ElseIf !NameInSet(ubeSet, MorphNames[i])
			anyOther = true
		EndIf
		i += 1
	EndWhile
	Bool pureUbe = anyUbeOnly && !anyOther

	i = 0
	While i < count
		If pureUbe || IsUbeOnlyName(MorphNames[i], ubeSet)
			MorphBody[i] = BODY_UBE
		EndIf
		i += 1
	EndWhile

	If pureUbe
		count = AppendMorphSet(FullMorphSet(), BODY_MAIN, count)
	EndIf
	count = AppendMorphSet(MainSwellSet(), BODY_MAIN, count)
	count = AppendMorphSet(ubeSet, BODY_UBE, count)
	AppendMorphSet(UbeSwellSet(), BODY_UBE, count)

	TableVersion = CurrentTableVersion
	Debug.Trace("ABM: morph table upgraded to per-body slots (" + MorphCount() + " morphs)")
EndFunction

Bool Function NameInSet(String[] names, String morphName)
	{True when morphName is in the list. Papyrus string compare is
	 case-insensitive, as slider names are.}
	Int i = 0
	While i < names.Length
		If names[i] == morphName
			Return true
		EndIf
		i += 1
	EndWhile
	Return false
EndFunction

Bool Function IsUbeOnlyName(String morphName, String[] ubeSet)
	{True for a UBE slider name no other supported body has -- the only names
	 that prove a slot was meant for UBE. See EnsureBodyTables. ubeSet is
	 UbeMorphSet(), passed in so a loop builds it once.}
	If morphName == "NippleLength" || morphName == "ClitorisErection" || morphName == "PussyCute"
		Return false
	EndIf
	If morphName == "BreastsBigger" || morphName == "GluteSize p|n"
		; UBE's swell pair (UbeSwellSet), which the table list doesn't carry.
		Return true
	EndIf
	Return NameInSet(ubeSet, morphName)
EndFunction

Int Function BodyOf(Actor who)
	{Which table an actor takes: BODY_UBE for a UBE race, BODY_MAIN for everyone
	 else. UBE is the one body that can be told apart per actor, because it
	 ships its own playable races and every one of them has "UBE_" in its
	 EditorID (00UBE_BretonRace, 00UBE_CustomRace01, ...). CBBE 3BA and BHUNP
	 both sit on the vanilla races, so nothing distinguishes them per actor:
	 they share the main table, and which of the two it holds is the install's
	 business. Find is case-insensitive. Mirrored by BodyOf in the DLL's
	 MorphApplier.cpp -- keep the two tests identical.}
	If StringUtil.Find(MiscUtil.GetActorRaceEditorID(who), "UBE_") >= 0
		Return BODY_UBE
	EndIf
	Return BODY_MAIN
EndFunction

String Function MorphKey(Int slot)
	{The JSON value key of one slot, for morph.json and the intensity presets.
	 A UBE slot is prefixed, because a file has one key per name and the same
	 name can be in both tables. JsonUtil lowercases keys on its own.}
	If MorphBody[slot] == BODY_UBE
		Return "ube_" + MorphNames[slot]
	EndIf
	Return MorphNames[slot]
EndFunction

Function RebuildMorphTables()
	{Resolve suppress.json against the current MorphNames into MorphSuppressed.

	 Each rule is either an area keyword (matched through GroupForMorph, so one
	 file covers every body's slider names) or an exact morph name. A missing
	 file or an empty list falls back to nipples alone: deleting the file must
	 not silently switch suppression off and leave nipples clipping through
	 tops. To suppress nothing, use the MCM toggle -- that is what it is for.

	 Called from ResetDefaults (every path that rewrites the table) and from
	 OnPlayerLoadGame, which is what makes a hand-edited file take effect.}
	MorphSuppressed = new int[128]
	AnyMorphSuppressed = false
	If !MorphBody
		; Never None for the writer, whatever state the save is in. All zeros
		; means "every slot is the main table", which is what a table that has
		; not been through EnsureBodyTables yet holds.
		MorphBody = new int[128]
	EndIf
	If !MorphNames
		; Corrupt / not-yet-built table (the state "Reset all state" exists to
		; recover from). Indexing it would throw and take the rest of
		; OnPlayerLoadGame -- requirements, SLA flavor, the poll -- down with it.
		return
	EndIf

	String[] rules = new String[128]
	Int ruleCount = 0
	If JsonUtil.Load(SuppressFile)
		Int listed = JsonUtil.StringListCount(SuppressFile, "suppress")
		While ruleCount < listed && ruleCount < 128
			rules[ruleCount] = JsonUtil.StringListGet(SuppressFile, "suppress", ruleCount)
			ruleCount += 1
		EndWhile
		JsonUtil.Unload(SuppressFile, false, false)
	EndIf
	If ruleCount == 0
		rules[0] = "nipples"
		ruleCount = 1
	EndIf

	Int i = 0
	While i < 128 && MorphNames[i] != ""
		String area = GroupKeyword(GroupForMorph(MorphNames[i]))
		Int r = 0
		While r < ruleCount
			; Papyrus string compare is case-insensitive, so a hand-typed
			; "Nipples" or "nipplesize" matches. No break: jump r past the end.
			If rules[r] == area || rules[r] == MorphNames[i]
				MorphSuppressed[i] = 1
				AnyMorphSuppressed = true
				r = ruleCount
			Else
				r += 1
			EndIf
		EndWhile
		i += 1
	EndWhile
EndFunction

Int[] Function GetMorphSuppressed()
	{The suppression flags, built on demand. The fallback is what fills them in
	 on a save made before they existed, where the property loads as None.}
	If !MorphSuppressed
		RebuildMorphTables()
	EndIf
	Return MorphSuppressed
EndFunction

Int[] Function GetMorphBody()
	{The body tag per slot, with the same on-demand fallback.}
	If !MorphBody
		RebuildMorphTables()
	EndIf
	Return MorphBody
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

String[] Function UbeMorphSet()
	{The UBE 2.0 slider list: the built-in UBE table, which UBE-race actors take
	 instead of the main one (see BodyOf). Names as in "UBE SE 2.0 Release
	 Body.osp". NippleLength is on both lists -- UBE has a slider of that name
	 too, with its own tuning, which is exactly why a body gets its own slots.}
	String[] names = new String[16]
	names[0]  = "NipplesPerkiness"
	names[1]  = "NippleLength"
	names[2]  = "AreolaErection"
	names[3]  = "NipplesShowUp"
	names[4]  = "NippleDiameter n|p"
	names[5]  = "AreolaeSizeBig"
	names[6]  = "AreolaeSizeSmall"
	names[7]  = "NippleInverted_PuffyAreola"
	names[8]  = "Nippleinverted"
	names[9]  = "Nipples_Fantasy"
	names[10] = "ClitorisErection"
	names[11] = "PussyCute"
	names[12] = "Vagina_shape"
	names[13] = "Vagina_shape_wider"
	names[14] = "Vagina_Fantasy"
	names[15] = "Vagina_spread"
	Return names
EndFunction

String[] Function MainSwellSet()
	{Breast and butt swell for the main table. Both names exist, and grow with a
	 POSITIVE value, on CBBE 3BA and on BHUNP alike (checked against both
	 bodies' BodySlide data), so one pair serves either install. Not Butt: that
	 slider grows on 3BA and shrinks on BHUNP. They default to 0, so the swell
	 is opt-in. Otherwise they are ordinary morphs: player and NPCs alike.}
	String[] names = new String[2]
	names[0] = "DoubleMelon"
	names[1] = "BigButt"
	Return names
EndFunction

String[] Function UbeSwellSet()
	{The same pair for the UBE table. A positive GluteSize is the bigger one,
	 despite the " p|n" in its name (checked against UBE's BodySlide data).}
	String[] names = new String[2]
	names[0] = "BreastsBigger"
	names[1] = "GluteSize p|n"
	Return names
EndFunction

Function ApplyMorphSet()
	{Rebuild the whole table at default values -- install / Reset only. Does NOT
	 preserve tuning; use EnsureFullMorphSet for a non-destructive upgrade.
	 Morphs the body doesn't define are no-ops.}
	MorphNames = new String[128]
	MaxValue   = new float[128]
	MorphBody  = new int[128]

	AppendAllSets(0)
	TableVersion = CurrentTableVersion

	ResetDefaults()
EndFunction

Function EnsureFullMorphSet()
	{Non-destructive upgrade: append missing morphs, preserving existing tuning.
	 No caller yet -- kept so a future addition to one of the built-in sets can
	 reach old saves without wiping their sliders.}
	AppendAllSets(MorphCount())
	ResetDefaults()
EndFunction

Function EnsureSwellSlots()
	{Append the swell entries to whichever table lacks them, at 0. For Import: a
	 file need not list them, and they should be on the page regardless.

	 Only on a table that already carries its body tags. An old-layout table
	 (TableVersion behind) gets them from EnsureBodyTables instead, which
	 rebuilds the tags from the names -- appending here first would hand it two
	 UBE-tagged slots it then has to guess about.}
	If TableVersion < CurrentTableVersion
		return
	EndIf
	Int count = AppendMorphSet(MainSwellSet(), BODY_MAIN, MorphCount())
	AppendMorphSet(UbeSwellSet(), BODY_UBE, count)
EndFunction

Int Function AppendAllSets(Int count)
	{Append whatever the two tables lack of their built-in sets, main first.
	 Returns the new count.}
	count = AppendMorphSet(FullMorphSet(), BODY_MAIN, count)
	count = AppendMorphSet(MainSwellSet(), BODY_MAIN, count)
	count = AppendMorphSet(UbeMorphSet(), BODY_UBE, count)
	Return AppendMorphSet(UbeSwellSet(), BODY_UBE, count)
EndFunction

Int Function AppendMorphSet(String[] names, Int body, Int count)
	{Append every listed name that body's table doesn't hold yet, at its
	 default. Returns the new count.}
	Int i = 0
	While i < names.Length
		count = AddMorphIfMissing(names[i], count, body)
		i += 1
	EndWhile
	Return count
EndFunction

Int Function AddMorphIfMissing(String morphName, Int count, Int body = 0)
	{Append morphName to one body's table if that table lacks it, returning the
	 new count. The same name on the OTHER body's table is not a match. Bounded
	 to 128.}
	If count >= 128
		Return count
	EndIf
	Int i = 0
	While i < count
		If MorphNames[i] == morphName && MorphBody[i] == body
			Return count
		EndIf
		i += 1
	EndWhile
	MorphNames[count] = morphName
	MorphBody[count]  = body
	MaxValue[count]   = DefaultForMorph(morphName, body)
	Return count + 1
EndFunction

Float Function DefaultForMorph(String morphName, Int body = 0)
	{Per-morph defaults (Natural tier -- keep in sync with Natural.json), per
	 BODY, since one name can default differently on each (NippleLength). Main
	 table: nipples use the Default* properties and the genital set lists only
	 non-zero values. Everything else, the swell entries included, is 0.}
	If body == BODY_UBE
		If morphName == "NipplesPerkiness"
			Return 0.8
		ElseIf morphName == "NippleLength"
			Return 0.3
		ElseIf morphName == "AreolaErection"
			Return 0.6
		ElseIf morphName == "ClitorisErection"
			Return 0.5
		EndIf
		Return 0.0
	EndIf
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
	 0 Nipples, 1 Areolas, 2 Vagina, 3 Breasts, 4 Butt, 5 Other. Find is
	 case-insensitive, and order is priority -- "nipple" wins over "areola" in
	 one name. Breasts and Butt are the swell groups (IsSwellGroup). The ids are
	 never persisted, only compared, and Other stays last so it draws last.}
	If StringUtil.Find(morphName, "nipple") >= 0
		Return 0
	ElseIf StringUtil.Find(morphName, "areola") >= 0
		Return 1
	ElseIf StringUtil.Find(morphName, "labia") >= 0 || StringUtil.Find(morphName, "vagina") >= 0 || StringUtil.Find(morphName, "pussy") >= 0 || StringUtil.Find(morphName, "clit") >= 0 || StringUtil.Find(morphName, "innie") >= 0 || StringUtil.Find(morphName, "cute") >= 0
		Return 2
	ElseIf StringUtil.Find(morphName, "breast") >= 0 || StringUtil.Find(morphName, "melon") >= 0
		Return 3
	ElseIf StringUtil.Find(morphName, "butt") >= 0 || StringUtil.Find(morphName, "glute") >= 0 || StringUtil.Find(morphName, "cheek") >= 0
		Return 4
	EndIf
	Return 5
EndFunction

; How many area groups GroupForMorph can return; the MCM draws them in id order.
int Property GroupCount = 6 AutoReadOnly Hidden

Bool Function IsSwellGroup(Int groupId)
	{True for Breasts and Butt, where the built-in swell entries live. Only the
	 MCM asks: those sliders get their own help line (off until raised, and not
	 flattened under armor). The writer treats them like any other morph.}
	Return groupId == 3 || groupId == 4
EndFunction

String Function GroupKeyword(Int groupId)
	{The suppress.json spelling of an area group. Deliberately NOT GroupName:
	 that one returns a "$ABM_*" translation key for the MCM headers, and a
	 hand-edited file must not be language-dependent.}
	If groupId == 0
		Return "nipples"
	ElseIf groupId == 1
		Return "areolas"
	ElseIf groupId == 2
		Return "vagina"
	ElseIf groupId == 3
		Return "breasts"
	ElseIf groupId == 4
		Return "butt"
	EndIf
	Return "other"
EndFunction

Bool Function UnderArmorActive()
	{True when suppression is on AND the resolved list actually covers a morph
	 in the current table. With nothing to scale, the armor handlers and the
	 writer skip the covered test entirely.}
	If !SuppressUnderArmor
		Return false
	EndIf
	If !MorphSuppressed
		RebuildMorphTables()
	EndIf
	Return AnyMorphSuppressed
EndFunction

String Function GroupName(Int groupId)
	{Display name of an area group (MCM section headers).}
	If groupId == 0
		Return "$ABM_Group_Nipples"
	ElseIf groupId == 1
		Return "$ABM_Group_Areolas"
	ElseIf groupId == 2
		Return "$ABM_Group_Vagina"
	ElseIf groupId == 3
		Return "$ABM_Group_Breasts"
	ElseIf groupId == 4
		Return "$ABM_Group_Butt"
	EndIf
	Return "$ABM_Group_Other"
EndFunction
