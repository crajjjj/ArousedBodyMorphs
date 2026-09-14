#include "Backend.h"

namespace ABM::Backend
{
	namespace
	{
		// SexlabArousedNG.dll exports (its include/ArousalAPI.h).
		using SLA_GetArousalInt_t = int32_t (*)(RE::Actor*);
		using SLA_GetInterfaceVersion_t = uint32_t (*)();

		// OSLAroused.dll exports (its src/Managers/ArousalManager.h).
		using OSL_GetArousalExt_t = float (*)(RE::Actor*);

		std::atomic<Kind>   g_kind{ Kind::kNone };
		SLA_GetArousalInt_t g_slaGetArousalInt = nullptr;
		OSL_GetArousalExt_t g_oslGetArousalExt = nullptr;
	}

	void Probe()
	{
		if (auto sla = ::GetModuleHandleA("SexlabArousedNG.dll")) {
			g_slaGetArousalInt = reinterpret_cast<SLA_GetArousalInt_t>(
				::GetProcAddress(sla, "SLA_GetArousalInt"));
			if (g_slaGetArousalInt) {
				g_kind.store(Kind::kSlaNg);
				uint32_t apiVersion = 0;
				if (auto getVer = reinterpret_cast<SLA_GetInterfaceVersion_t>(
						::GetProcAddress(sla, "SLA_GetInterfaceVersion"))) {
					apiVersion = getVer();
				}
				logger::info("Backend: SexLab Aroused NG (C API v{})", apiVersion);
				return;
			}
			// Present but too old for the C API -- Papyrus still covers it.
			logger::warn("SexlabArousedNG.dll found but SLA_GetArousalInt missing (pre-API build?) - staying on the Papyrus path for it");
		}

		if (auto osl = ::GetModuleHandleA("OSLAroused.dll")) {
			g_oslGetArousalExt = reinterpret_cast<OSL_GetArousalExt_t>(
				::GetProcAddress(osl, "GetArousalExt"));
			if (g_oslGetArousalExt) {
				g_kind.store(Kind::kOsl);
				logger::info("Backend: OSL Aroused (GetArousalExt + OSLA_ActorArousalUpdated events)");
				return;
			}
			logger::warn("OSLAroused.dll found but GetArousalExt missing (old build?) - staying on the Papyrus path for it");
		}

		g_kind.store(Kind::kNone);
		logger::info("Backend: none (no native arousal DLL) - Papyrus pipeline stays in charge");
	}

	Kind GetKind()
	{
		return g_kind.load();
	}

	const char* Describe()
	{
		switch (g_kind.load()) {
		case Kind::kSlaNg:
			return "SLA NG (native poll + heartbeat)";
		case Kind::kOsl:
			return "OSL Aroused (event-driven)";
		default:
			return "none - Papyrus mode";
		}
	}

	int GetArousal(RE::Actor* who)
	{
		if (!who) {
			return -1;
		}
		switch (g_kind.load()) {
		case Kind::kSlaNg:
			// Already clamped 0-100 by the exporter.
			return g_slaGetArousalInt ? g_slaGetArousalInt(who) : -1;
		case Kind::kOsl:
			if (!g_oslGetArousalExt) {
				return -1;
			}
			return std::clamp(static_cast<int>(std::lround(g_oslGetArousalExt(who))), 0, 100);
		default:
			return -1;
		}
	}
}
