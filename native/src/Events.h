#pragma once

// Event-driven update paths:
//
//   OSL Aroused  per-actor OSLA_ActorArousalUpdated -> that actor. No polling.
//   SLA NG       sla_UpdateComplete -> player + nearby sweep, plus a native
//                player poll at the MCM interval (the Papyrus poll, off the VM).
//   both         player TESEquipEvent -> under-armor refresh. Snaps; the
//                Papyrus reveal tween is not reproduced natively yet.
//
// All engine work runs on the main thread via task interface; sinks only
// classify + queue.

namespace ABM::Events
{
	// Register the mod-event + equip sinks. Call once at kDataLoaded.
	void RegisterSinks();

	// Player-poll thread; runs for the process but no-ops unless backend is
	// SLA NG, the mod is enabled and pollInterval > 0. Call after Probe().
	void StartPollThread();

	// Wake the poll thread so a changed PollInterval takes effect now.
	void NotifyConfigChanged();
}
