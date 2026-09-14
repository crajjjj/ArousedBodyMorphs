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

		// Resolved once at kDataLoaded (ResolveForms). Forms are stable for
		// the lifetime of the process once data is loaded, and eager
		// resolution keeps the update paths free of lazy-init races (they run
		// on the main thread AND, for the evaluation half, the Papyrus VM).
		RE::BGSKeyword* g_kwArmorCuirass = nullptr;
		RE::BGSKeyword* g_kwClothingBody = nullptr;
		RE::BGSKeyword* g_kwActorTypeNPC = nullptr;
		RE::TESFaction* g_andNude = nullptr;
		RE::TESFaction* g_andTopless = nullptr;

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

		// Filters + fresh arousal read + under-armor scale. No SKEE calls, so
		// safe from any thread (form/AV reads, same class as Papyrus natives).
		// Returns the arousal in effect (outScale set), or -1/-2 per the
		// header contract.
		int Evaluate(RE::Actor* who, float& outScale)
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

			// Actor filters -- same split as the Papyrus UpdateActor: sex from
			// the ActorBase (SEX::kNone/-1 counts as male, as in Papyrus),
			// creature-ness from the race's ActorTypeNPC keyword.
			auto base = who->GetActorBase();
			if (!base) {
				return -2;
			}
			auto race = who->GetRace();
			const bool isCreature = race && g_kwActorTypeNPC && !race->HasKeyword(g_kwActorTypeNPC);
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
			arousal = std::clamp(arousal, 0, 100);

			outScale = 1.0f;
			if (cfg->suppressUnderArmor && IsTopCovered(who)) {
				outScale = cfg->underArmorScale;
			}
			return arousal;
		}

		// The SKEE write half. MAIN THREAD ONLY: ApplyBodyMorphs does direct
		// geometry work on the ref's loaded 3D. Re-checks the cheap gates --
		// when queued from the VM the world may have moved on by the time the
		// task runs (mod switched off, 3D unloaded).
		void ApplyMorphs(RE::Actor* who, int arousal, float armorScale)
		{
			if (!who || !g_bodyMorph) {
				return;
			}
			auto cfg = Settings::Snapshot();
			if (!cfg->modEnabled || cfg->morphs.empty() || !who->Is3DLoaded()) {
				return;
			}

			const float factor = static_cast<float>(arousal) / 100.0f * armorScale;

			// Unchanged-value skip. Every slot is maxValue * the same factor,
			// so one slot settles whether anything would change -- and asking
			// SKEE what WE last wrote (our key only) makes SKEE the single
			// source of truth: no parallel cache to invalidate on a settings
			// push, a save load, or an external clear, and the comparison
			// target moves with the settings on its own. Skipping here avoids
			// the ApplyBodyMorphs mesh rebuild, which is the real cost.
			// Probe slot = first non-zero max; a zero-max slot reads 0 for
			// every factor and could never detect a change.
			const MorphEntry* probe = nullptr;
			for (const auto& morph : cfg->morphs) {
				if (morph.maxValue != 0.0f) {
					probe = &morph;
					break;
				}
			}
			if (!probe) {
				return;  // every max is 0 -- this table can never write anything
			}
			const float current = g_bodyMorph->GetMorph(who, probe->name.c_str(), NIO_KEY);
			if (std::fabs(current - probe->maxValue * factor) < 1e-6f) {
				return;
			}

			for (const auto& morph : cfg->morphs) {
				const float value = morph.maxValue * factor;
				g_bodyMorph->SetMorph(who, morph.name.c_str(), NIO_KEY, value);
			}
			g_bodyMorph->ApplyBodyMorphs(who);

			if (cfg->debugMode) {
				logger::info("ApplyMorphs: {} arousal={} scale={} ({} morphs)",
					who->GetDisplayFullName(), arousal, armorScale, cfg->morphs.size());
			}
		}
	}

	void ResolveSkee()
	{
		auto messaging = SKSE::GetMessagingInterface();
		if (!messaging) {
			logger::warn("SKSE messaging interface unavailable - native morph writes disabled");
			return;
		}
		SKEE::InterfaceExchangeMessage msg;
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

	void ResolveForms()
	{
		g_kwArmorCuirass = RE::TESForm::LookupByEditorID<RE::BGSKeyword>("ArmorCuirass");
		g_kwClothingBody = RE::TESForm::LookupByEditorID<RE::BGSKeyword>("ClothingBody");
		g_kwActorTypeNPC = RE::TESForm::LookupByEditorID<RE::BGSKeyword>("ActorTypeNPC");
		if (auto dataHandler = RE::TESDataHandler::GetSingleton()) {
			// Same formIDs SLA NG resolves in slamainscr.psc -- AND owns them.
			g_andNude = dataHandler->LookupForm<RE::TESFaction>(0x831, AND_PLUGIN);
			g_andTopless = dataHandler->LookupForm<RE::TESFaction>(0x832, AND_PLUGIN);
		}
		logger::info("Form lookups: cuirass={} clothing={} actorTypeNPC={} AND={}",
			g_kwArmorCuirass != nullptr, g_kwClothingBody != nullptr,
			g_kwActorTypeNPC != nullptr, g_andNude || g_andTopless);
	}

	bool SkeeReady()
	{
		return g_bodyMorph != nullptr;
	}

	int UpdateActor(RE::Actor* who)
	{
		float scale = 1.0f;
		const int arousal = Evaluate(who, scale);
		if (arousal >= 0) {
			ApplyMorphs(who, arousal, scale);
		}
		return arousal;
	}

	int UpdateActorDeferred(RE::Actor* who)
	{
		float scale = 1.0f;
		const int arousal = Evaluate(who, scale);
		if (arousal >= 0) {
			RE::ActorHandle handle = who->GetHandle();
			SKSE::GetTaskInterface()->AddTask([handle, arousal, scale]() {
				if (auto actorPtr = handle.get()) {
					ApplyMorphs(actorPtr.get(), arousal, scale);
				}
			});
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

	void ClearActorDeferred(RE::Actor* who)
	{
		if (!who || !g_bodyMorph) {
			return;
		}
		RE::ActorHandle handle = who->GetHandle();
		SKSE::GetTaskInterface()->AddTask([handle]() {
			if (auto actorPtr = handle.get()) {
				ClearActor(actorPtr.get());
			}
		});
	}
}
