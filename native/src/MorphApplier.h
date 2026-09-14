#pragma once

// The native morph writer: mirrors ABM_PlayerAlias.UpdateActor semantics
// (actor filters, arousal read, under-armor suppression, per-morph write under
// the "ArousedBodyMorphs.esp" NIO key) against SKEE's IBodyMorphInterface --
// one native call chain instead of 23 Papyrus->native round trips.

namespace ABM::MorphApplier
{
	// Acquire SKEE's BodyMorph interface via SKSE messaging ("skee" +
	// InterfaceExchangeMessage). Call at kDataLoaded.
	void ResolveSkee();

	bool SkeeReady();

	// Update one actor from a fresh backend arousal read (+ modifier, clamped
	// 0-100). Returns the arousal written, or:
	//   -1  backend/SKEE unavailable
	//   -2  skipped (mod disabled, actor filters, no 3D)
	int UpdateActor(RE::Actor* who, int modifier = 0);

	// Drop every morph under our NIO key for the actor (mirror of the Papyrus
	// ClearActorMorphs).
	void ClearActor(RE::Actor* who);
}
