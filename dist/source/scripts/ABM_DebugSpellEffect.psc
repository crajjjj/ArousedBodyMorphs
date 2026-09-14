Scriptname ABM_DebugSpellEffect extends ActiveMagicEffect
{Lesser power: dump base + morph info for the crosshair target (or the player),
 force an UpdateActor, and dump again. Granted by the MCM Debug mode toggle.}

ABM_PlayerAlias Property PlayerAlias Auto

Event OnEffectStart(Actor akTarget, Actor akCaster)

	printf("=ABM_DEBUG_SCRIPT_START=")

	Actor Who = Game.GetCurrentCrosshairRef() as Actor

	If(Who == None)
		Who = Game.GetPlayer()
	EndIf

	analyzeBase(who)
	analyzeMorphs(who)

	printf("- FORCING UPDATE NOW -")
	PlayerAlias.UpdateActor(Who, true)

	analyzeMorphs(who)

	printf("=ABM_DEBUG_SCRIPT_END=")
EndEvent


function print(string str)
	debug.trace(str)
	;debug.notification(str)
endfunction

function printf(string str)
	print("abm_debug ||"+str)
endfunction

function analyzeBase(Actor who)
	ActorBase base = who.getLeveledActorBase()

	debug.notification("ABM DEBUG: Analyzing "+base.getName())
	debug.notification("ABM DEBUG: See Papyrus log")

	printf("Analyzing "+who)
	printf("-----")

	printf("Name: "+base.getName())
	printf("Race: "+base.getRace())
	printf("Sex: "+base.getSex())
	printf("-----")

	printf("TRI file CBBE: "+NiOverride.getStringExtraData(who,false, "BaseShape", "BODYTRI"))
	printf("TRI file UUNP: "+NiOverride.getStringExtraData(who,false, "UUNP", "BODYTRI"))
	printf("TRI file 3BA: "+NiOverride.getStringExtraData(who,false, "3BA", "BODYTRI"))
	printf("-----")
endFunction

function analyzeMorphs(Actor who)
	ActorBase base = who.getLeveledActorBase()

	printf("Current BodyMorphs: ")

	string[] morphs = NiOverride.getMorphNames(who)
	int i = morphs.length
	while i
		i -= 1
		string[] keys = NiOverride.getMorphKeys(who, morphs[i])

		int j = keys.length
		while j
			j -= 1
			float value = NiOverride.getBodyMorph(who, morphs[i], keys[j])
			printf("  Key "+keys[j]+" on Morph "+morphs[i]+" at "+value)
		endWhile
	endWhile
	printf("-----")
endFunction
