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

		// Resolved once at kDataLoaded. Forms are process-stable after that,
		// and eager resolution keeps the update paths free of lazy-init races
		// (they run on the main thread AND the Papyrus VM).
		RE::BGSKeyword* g_kwArmorCuirass = nullptr;
		RE::BGSKeyword* g_kwClothingBody = nullptr;
		RE::BGSKeyword* g_kwActorTypeNPC = nullptr;
		RE::TESFaction* g_andNude = nullptr;
		RE::TESFaction* g_andTopless = nullptr;
		RE::TESFaction* g_andShowingChest = nullptr;

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

		// True when AND reports the chest exposed. Nude/Topless mean nothing on
		// the chest at all; ShowingChest is the one that catches a top that IS
		// worn but leaves the breasts out, which is the point of the override.
		bool ANDSaysBare(RE::Actor* who)
		{
			return HasFactionRankOne(who, g_andNude) ||
			       HasFactionRankOne(who, g_andTopless) ||
			       HasFactionRankOne(who, g_andShowingChest);
		}

		// Papyrus Actor.WornHasKeyword, for either top keyword in one pass.
		// Every worn slot counts, not just 32: bras and bikini tops routinely
		// sit on 46 or 56 with the body slot empty. One GetInventory walk is
		// what a single GetWornArmor call already costs.
		bool WornHasTopKeyword(RE::Actor* who)
		{
			const auto inv = who->GetInventory([](RE::TESBoundObject& a_object) {
				return a_object.IsArmor();
			});

			for (const auto& [item, invData] : inv) {
				const auto& [count, entry] = invData;
				if (count > 0 && entry && entry->IsWorn()) {
					const auto armor = item->As<RE::TESObjectARMO>();
					if (armor &&
						((g_kwArmorCuirass && armor->HasKeyword(g_kwArmorCuirass)) ||
							(g_kwClothingBody && armor->HasKeyword(g_kwClothingBody)))) {
						return true;
					}
				}
			}
			return false;
		}

		// Mirror of ABM_PlayerAlias.IsTopCovered: the keyword check is primary,
		// AND only OVERRIDES covered->bare. AND is what demotes an accessory
		// that merely inherited ClothingBody (a corset, a piercing) back to
		// bare, since it leaves the breasts visible and so ranks ShowingChest.
		bool IsTopCovered(RE::Actor* who)
		{
			if (!WornHasTopKeyword(who)) {
				// Naked-body armors / SOS carry neither keyword -> bare.
				return false;
			}
			return !ANDSaysBare(who);
		}

		// Filters + arousal read + under-armor scale. No SKEE calls, so safe
		// from any thread. Returns arousal (outScale set) or -1/-2.
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

			// Same split as the Papyrus UpdateActor: sex from the ActorBase
			// (kNone counts as male), creature-ness from the race keyword.
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

			// With no morph flagged the feature does nothing, so the covered
			// test (an inventory walk) isn't worth running.
			outScale = 1.0f;
			if (cfg->suppressUnderArmor && cfg->anySuppressed && IsTopCovered(who)) {
				outScale = cfg->underArmorScale;
			}
			return arousal;
		}

		// The SKEE write half. MAIN THREAD ONLY: ApplyBodyMorphs does direct
		// geometry work. Re-checks the cheap gates, since when queued from the
		// VM the world may have moved on by the time the task runs.
		void ApplyMorphs(RE::Actor* who, int arousal, float armorScale)
		{
			if (!who || !g_bodyMorph) {
				return;
			}
			auto cfg = Settings::Snapshot();
			if (!cfg->modEnabled || cfg->morphs.empty() || !who->Is3DLoaded()) {
				return;
			}

			// Two factors, not one: the scale reaches only the morphs flagged by
			// suppress.json (the covered test is a CHEST test, so e.g. a vagina
			// slider has no business being flattened by it). A scale of 1.0
			// collapses them, which is the uncovered case.
			const float bare = static_cast<float>(arousal) / 100.0f;
			const float covered = bare * armorScale;
			const bool mixed = armorScale != 1.0f;
			const auto suppressed = [&](const MorphEntry& morph) {
				return mixed && morph.suppressed;
			};

			// Unchanged-value skip: every slot takes one of those two factors,
			// so ONE PROBE PER FACTOR settles whether anything would change --
			// a single probe would miss changes confined to the other factor.
			// Reading back what WE wrote (our key) makes SKEE the source of
			// truth: no parallel cache to invalidate on a push, a load, or an
			// external clear. Skipping avoids the ApplyBodyMorphs rebuild, the
			// real cost. Probes must have a non-zero max; a zero-max slot reads
			// 0 for every factor and could never detect a change.
			const MorphEntry* probeBare = nullptr;
			const MorphEntry* probeCovered = nullptr;
			for (const auto& morph : cfg->morphs) {
				if (morph.maxValue == 0.0f) {
					continue;
				}
				if (suppressed(morph)) {
					if (!probeCovered) {
						probeCovered = &morph;
					}
				} else if (!probeBare) {
					probeBare = &morph;
				}
			}
			if (!probeBare && !probeCovered) {
				return;  // every max is 0 -- this table can never write anything
			}
			const auto atTarget = [&](const MorphEntry* probe, float factor) {
				if (!probe) {
					return true;
				}
				const float current = g_bodyMorph->GetMorph(who, probe->name.c_str(), NIO_KEY);
				return std::fabs(current - probe->maxValue * factor) < 1e-6f;
			};
			if (atTarget(probeBare, bare) && atTarget(probeCovered, covered)) {
				if (cfg->debugMode) {
					// Say so explicitly, so a debug session can tell "already
					// correct" from "never ran".
					logger::info("ApplyMorphs: {} already at target (factor {}, covered {})",
						who->GetDisplayFullName(), bare, covered);
				}
				return;
			}

			for (const auto& morph : cfg->morphs) {
				const float value = morph.maxValue * (suppressed(morph) ? covered : bare);
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
			g_andShowingChest = dataHandler->LookupForm<RE::TESFaction>(0x82F, AND_PLUGIN);
		}
		logger::info("Form lookups: cuirass={} clothing={} actorTypeNPC={} AND={}",
			g_kwArmorCuirass != nullptr, g_kwClothingBody != nullptr,
			g_kwActorTypeNPC != nullptr, g_andNude || g_andTopless || g_andShowingChest);
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
