#include "MorphApplier.h"

#include "Backend.h"
#include "SKEE.h"
#include "Settings.h"

namespace ABM::MorphApplier
{
	namespace
	{
		constexpr const char* NIO_KEY = "ArousedBodyMorphs.esp";
		constexpr const char* AND_PLUGIN = "Advanced Nudity Detection.esp";

		SKEE::IBodyMorphInterface* g_bodyMorph = nullptr;

		// Lazily-resolved lookups for the under-armor check. Forms are stable
		// for the lifetime of the process once data is loaded.
		RE::BGSKeyword* g_kwArmorCuirass = nullptr;
		RE::BGSKeyword* g_kwClothingBody = nullptr;
		RE::TESFaction* g_andNude = nullptr;
		RE::TESFaction* g_andTopless = nullptr;
		bool            g_lookupsDone = false;

		void ResolveLookups()
		{
			if (g_lookupsDone) {
				return;
			}
			g_kwArmorCuirass = RE::TESForm::LookupByEditorID<RE::BGSKeyword>("ArmorCuirass");
			g_kwClothingBody = RE::TESForm::LookupByEditorID<RE::BGSKeyword>("ClothingBody");
			if (auto dataHandler = RE::TESDataHandler::GetSingleton()) {
				// Same formIDs SLA NG resolves in slamainscr.psc -- AND owns them.
				g_andNude = dataHandler->LookupForm<RE::TESFaction>(0x831, AND_PLUGIN);
				g_andTopless = dataHandler->LookupForm<RE::TESFaction>(0x832, AND_PLUGIN);
			}
			g_lookupsDone = true;
			logger::info("Under-armor lookups: cuirass={} clothing={} AND={}",
				g_kwArmorCuirass != nullptr, g_kwClothingBody != nullptr,
				g_andNude || g_andTopless);
		}

		bool HasFactionRankOne(RE::Actor* who, RE::TESFaction* faction)
		{
			if (!faction) {
				return false;
			}
			bool match = false;
			who->VisitFactions([&](RE::TESFaction* a_faction, std::int8_t a_rank) {
				if (a_faction == faction && a_rank == 1) {
					match = true;
					return true;
				}
				return false;
			});
			return match;
		}

		// Mirror of ABM_PlayerAlias.IsTopCovered: vanilla body-slot keyword
		// check first, Advanced Nudity Detection only OVERRIDES covered->bare
		// (so unscanned NPCs still read correctly). Papyrus used WornHasKeyword
		// (any worn item); the cuirass/clothing keywords live on body-slot
		// armor, so checking slot 32 is the practical equivalent.
		bool IsTopCovered(RE::Actor* who)
		{
			ResolveLookups();
			auto wornBody = who->GetWornArmor(RE::BGSBipedObjectForm::BipedObjectSlot::kBody);
			if (!wornBody) {
				return false;
			}
			bool keyworded = (g_kwArmorCuirass && wornBody->HasKeyword(g_kwArmorCuirass)) ||
			                 (g_kwClothingBody && wornBody->HasKeyword(g_kwClothingBody));
			if (!keyworded) {
				// Naked-body armors / SOS carry neither keyword -> bare.
				return false;
			}
			if (HasFactionRankOne(who, g_andNude) || HasFactionRankOne(who, g_andTopless)) {
				return false;
			}
			return true;
		}
	}

	void ResolveSkee()
	{
		SKEE::InterfaceExchangeMessage msg;
		auto messaging = SKSE::GetMessagingInterface();
		messaging->Dispatch(SKEE::InterfaceExchangeMessage::kExchangeInterface, &msg,
			sizeof(SKEE::InterfaceExchangeMessage*), "skee");
		if (!msg.interfaceMap) {
			logger::warn("SKEE interface map unavailable (RaceMenu missing?) - native morph writes disabled");
			return;
		}
		g_bodyMorph = static_cast<SKEE::IBodyMorphInterface*>(msg.interfaceMap->QueryInterface("BodyMorph"));
		if (!g_bodyMorph) {
			logger::warn("SKEE BodyMorph interface unavailable - native morph writes disabled");
			return;
		}
		logger::info("SKEE BodyMorph interface acquired (version {})", g_bodyMorph->GetVersion());
	}

	bool SkeeReady()
	{
		return g_bodyMorph != nullptr;
	}

	int UpdateActor(RE::Actor* who, int modifier)
	{
		if (!who || !g_bodyMorph || Backend::GetKind() == Backend::Kind::kNone) {
			return -1;
		}
		auto cfg = Settings::Snapshot();
		if (!cfg->modEnabled || cfg->morphs.empty()) {
			return -2;
		}
		if (!who->Is3DLoaded()) {
			return -2;
		}

		// Actor filters -- same split as the Papyrus UpdateActor: sex from the
		// ActorBase, creature-ness from the race (Papyrus GetSex() folds both;
		// natively a race without ActorTypeNPC is a creature).
		auto base = who->GetActorBase();
		if (!base) {
			return -2;
		}
		auto race = who->GetRace();
		const bool isCreature = race && !race->HasKeywordString("ActorTypeNPC");
		const bool isFemale = base->GetSex() == RE::SEX::kFemale;
		if (!isCreature && !isFemale && cfg->ignoreMales) {
			return -2;
		}
		if (isCreature && !isFemale && cfg->ignoreMaleBeast) {
			return -2;
		}
		if (isCreature && isFemale && cfg->ignoreFemaleBeast) {
			return -2;
		}
		if (cfg->ignoreDead && who->IsDead()) {
			return -2;
		}

		int arousal = Backend::GetArousal(who);
		if (arousal < 0) {
			return -1;
		}
		arousal = std::clamp(arousal + modifier, 0, 100);

		float armorScale = 1.0f;
		if (cfg->suppressUnderArmor && IsTopCovered(who)) {
			armorScale = cfg->underArmorScale;
		}

		for (const auto& morph : cfg->morphs) {
			const float value = morph.maxValue * static_cast<float>(arousal) / 100.0f * armorScale;
			g_bodyMorph->SetMorph(who, morph.name.c_str(), NIO_KEY, value);
		}
		g_bodyMorph->ApplyBodyMorphs(who);

		if (cfg->debugMode) {
			logger::info("UpdateActor: {} arousal={} scale={} ({} morphs)",
				who->GetDisplayFullName(), arousal, armorScale, cfg->morphs.size());
		}
		return arousal;
	}

	void ClearActor(RE::Actor* who)
	{
		if (!who || !g_bodyMorph) {
			return;
		}
		g_bodyMorph->ClearBodyMorphKeys(who, NIO_KEY);
		if (who->Is3DLoaded()) {
			g_bodyMorph->ApplyBodyMorphs(who);
		}
	}
}
