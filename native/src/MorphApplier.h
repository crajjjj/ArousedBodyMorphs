#pragma once

// The native morph writer: mirrors ABM_PlayerAlias.UpdateActor (filters,
// arousal read, under-armor scale, per-morph write under our NIO key) against
// SKEE, as one call chain instead of 23 Papyrus->native round trips.
//
// THREADING: UpdateActor / ClearActor do direct SKEE geometry work
// (ApplyBodyMorphs walks the loaded 3D) and are MAIN THREAD ONLY -- reach them
// from an SKSE task, never from a sink thread or the Papyrus VM. The *Deferred
// variants evaluate on the calling thread (form reads only) and queue the SKEE
// write; those are what the Papyrus bindings use.

namespace ABM::MorphApplier
{
	// Acquire SKEE's BodyMorph interface via SKSE messaging. Call at kDataLoaded.
	void ResolveSkee();

	// Resolve the keyword / faction lookups used by the under-armor check and
	// the creature filter. At kDataLoaded: forms are process-stable after that,
	// and resolving eagerly keeps the update paths race-free.
	void ResolveForms();

	bool SkeeReady();

	// Update one actor from a fresh arousal read. Returns the arousal in
	// effect, -1 backend/SKEE unavailable, -2 skipped (disabled, filters, no
	// 3D). The write is skipped when SKEE already holds these values (one
	// GetMorph probe), so a steady-state tick costs a read, not a rebuild --
	// and no cached state exists to go stale. MAIN THREAD ONLY.
	int UpdateActor(RE::Actor* who);

	// Same, callable from any thread: evaluates inline for the return code,
	// queues the SKEE write to the main thread.
	int UpdateActorDeferred(RE::Actor* who);

	// Drop every morph under our NIO key. Main-thread / any-thread as above.
	void ClearActor(RE::Actor* who);
	void ClearActorDeferred(RE::Actor* who);
}
