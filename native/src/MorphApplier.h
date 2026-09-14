#pragma once

// The native morph writer: mirrors ABM_PlayerAlias.UpdateActor semantics
// (actor filters, arousal read, under-armor suppression, per-morph write under
// the "ArousedBodyMorphs.esp" NIO key) against SKEE's IBodyMorphInterface --
// one native call chain instead of 23 Papyrus->native round trips.
//
// Threading contract: UpdateActor / ClearActor do direct SKEE geometry work
// (ApplyBodyMorphs walks the ref's loaded 3D) and are MAIN THREAD ONLY --
// call them from an SKSE task, never from an event sink thread or the Papyrus
// VM. The *Deferred variants evaluate on the calling thread (form/AV reads
// only, same class of reads every Papyrus native does) and queue the SKEE
// writes onto the task interface; they are what the Papyrus bindings use.

namespace ABM::MorphApplier
{
	// Acquire SKEE's BodyMorph interface via SKSE messaging ("skee" +
	// InterfaceExchangeMessage). Call at kDataLoaded.
	void ResolveSkee();

	// Resolve the keyword / faction lookups the under-armor check and the
	// creature filter use. Call at kDataLoaded (forms are process-stable
	// afterwards); resolving eagerly keeps the update paths lock- and
	// race-free.
	void ResolveForms();

	bool SkeeReady();

	// Update one actor from a fresh backend arousal read (clamped 0-100).
	// Returns the arousal in effect, or:
	//   -1  backend/SKEE unavailable
	//   -2  skipped (mod disabled, actor filters, no 3D)
	// The morph write itself is skipped when SKEE already holds the values
	// this update would write (one GetMorph probe under our key) -- so a
	// steady-state poll tick costs an arousal read, not a mesh rebuild, and
	// there is no cached state that could go stale.
	// MAIN THREAD ONLY.
	int UpdateActor(RE::Actor* who);

	// Same evaluation, but callable from any thread (Papyrus VM): filters and
	// the arousal read run inline so the caller gets the return code, the SKEE
	// writes are queued to the main thread.
	int UpdateActorDeferred(RE::Actor* who);

	// Drop every morph under our NIO key for the actor (mirror of the Papyrus
	// ClearActorMorphs). MAIN THREAD ONLY / any-thread variant as above.
	void ClearActor(RE::Actor* who);
	void ClearActorDeferred(RE::Actor* who);
}
