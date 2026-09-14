#include "Papyrus.h"

#include "Backend.h"
#include "Events.h"
#include "MorphApplier.h"
#include "Settings.h"

// Bindings for ABM_Native.psc. Papyrus owns all persisted settings and mirrors
// them here via PushConfig/PushMorphTable on load and on any MCM change.

namespace ABM::Papyrus
{
	namespace
	{
		constexpr std::string_view PapyrusClass = "ABM_Native";

		bool IsActive(RE::StaticFunctionTag*)
		{
			return Backend::GetKind() != Backend::Kind::kNone && MorphApplier::SkeeReady();
		}

		RE::BSFixedString GetBackendName(RE::StaticFunctionTag*)
		{
			if (!MorphApplier::SkeeReady() && Backend::GetKind() != Backend::Kind::kNone) {
				return "$ABM_Backend_NoSkee";
			}
			return Backend::Describe();
		}

		int32_t UpdateActor(RE::StaticFunctionTag*, RE::Actor* who)
		{
			// Papyrus natives run on the VM thread: evaluate inline for the
			// return code, defer the SKEE write -- off-thread geometry work
			// races the renderer.
			return MorphApplier::UpdateActorDeferred(who);
		}

		void ClearActorMorphs(RE::StaticFunctionTag*, RE::Actor* who)
		{
			MorphApplier::ClearActorDeferred(who);
		}

		void PushConfig(RE::StaticFunctionTag*,
			bool modEnabled, bool ignoreMales, bool ignoreDead, bool ignoreMaleBeast,
			bool ignoreFemaleBeast, bool suppressUnderArmor, float underArmorScale,
			float pollInterval, float scanRadius, bool debugMode)
		{
			Config options;
			options.modEnabled = modEnabled;
			options.ignoreMales = ignoreMales;
			options.ignoreDead = ignoreDead;
			options.ignoreMaleBeast = ignoreMaleBeast;
			options.ignoreFemaleBeast = ignoreFemaleBeast;
			options.suppressUnderArmor = suppressUnderArmor;
			options.underArmorScale = underArmorScale;
			options.pollInterval = pollInterval;
			options.scanRadius = scanRadius;
			options.debugMode = debugMode;
			Settings::PushConfig(options);
			Events::NotifyConfigChanged();
			logger::info("Config pushed from Papyrus (enabled={}, poll={}s)", modEnabled, pollInterval);
		}

		void PushMorphTable(RE::StaticFunctionTag*,
			std::vector<RE::BSFixedString> names, std::vector<float> maxValues)
		{
			std::vector<MorphEntry> morphs;
			const size_t count = std::min(names.size(), maxValues.size());
			morphs.reserve(count);
			for (size_t i = 0; i < count; ++i) {
				// 128-slot arrays with trailing empties; stop at the first.
				if (names[i].empty()) {
					break;
				}
				morphs.push_back({ names[i].c_str(), maxValues[i] });
			}
			logger::info("Morph table pushed from Papyrus ({} morphs)", morphs.size());
			Settings::PushMorphTable(std::move(morphs));
		}
	}

	bool RegisterFunctions(RE::BSScript::IVirtualMachine* vm)
	{
		vm->RegisterFunction("IsActive", PapyrusClass, IsActive);
		vm->RegisterFunction("GetBackendName", PapyrusClass, GetBackendName);
		vm->RegisterFunction("UpdateActor", PapyrusClass, UpdateActor);
		vm->RegisterFunction("ClearActorMorphs", PapyrusClass, ClearActorMorphs);
		vm->RegisterFunction("PushConfig", PapyrusClass, PushConfig);
		vm->RegisterFunction("PushMorphTable", PapyrusClass, PushMorphTable);
		return true;
	}
}
