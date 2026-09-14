#pragma once

// Arousal backend detection + reads. Both frameworks export a C API from their
// SKSE DLL, resolved at runtime via GetProcAddress so we never link-depend:
//
//   SexlabArousedNG.dll  SLA_GetArousalInt -> int 0-100. No push events, so we
//                        poll the player and ride the sla_UpdateComplete sweep.
//   OSLAroused.dll       GetArousalExt -> float, plus per-actor
//                        OSLA_ActorArousalUpdated events. Fully event-driven.
//
// Legacy Papyrus-only forks export nothing: Backend stays kNone, the DLL does
// no morph work, and the Papyrus pipeline runs as before.

namespace ABM::Backend
{
	enum class Kind
	{
		kNone,
		kSlaNg,
		kOsl,
	};

	// Call once at kDataLoaded (all plugin DLLs loaded by then). Idempotent.
	void Probe();

	Kind GetKind();

	// Human-readable backend line for the MCM requirements row.
	const char* Describe();

	// Fresh arousal, clamped 0-100; -1 when unavailable or who is null.
	int GetArousal(RE::Actor* who);
}
