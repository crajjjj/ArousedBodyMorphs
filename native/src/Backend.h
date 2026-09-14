#pragma once

// Arousal backend detection + native reads. Both major frameworks export a C
// API from their SKSE DLL, resolved here at runtime via GetProcAddress so ABM
// never link-depends on either:
//
//   SexLab Aroused NG / SLO NG  (SexlabArousedNG.dll)
//     SLA_GetArousalInt(Actor*) -> int32 clamped 0-100   (ArousalAPI.h)
//     no push events -> we poll the player and ride the sla_UpdateComplete
//     heartbeat for NPCs.
//
//   OSL Aroused  (OSLAroused.dll)
//     GetArousalExt(Actor*) -> float                     (ArousalManager.h)
//     pushes OSLA_ActorArousalUpdated mod events per actor -> fully
//     event-driven, no polling at all.
//
// Legacy Papyrus-only forks (SSELoose, eXtended, SLAXSE) export nothing;
// Backend stays kNone and the Papyrus pipeline in ABM_PlayerAlias keeps
// running exactly as before -- the DLL then does no morph work.

namespace ABM::Backend
{
	enum class Kind
	{
		kNone,
		kSlaNg,
		kOsl,
	};

	// Resolve the backend. Call once at SKSE kDataLoaded (all plugin DLLs are
	// loaded by then); safe to call again (idempotent re-probe).
	void Probe();

	Kind GetKind();

	// Human-readable backend line for the MCM requirements row.
	const char* Describe();

	// Fresh arousal for the actor, clamped to 0-100. Returns -1 when no native
	// backend is available (or who is null).
	int GetArousal(RE::Actor* who);
}
