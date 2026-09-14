#pragma once

// Event-driven update paths:
//
//   OSL Aroused    OSLA_ActorArousalUpdated mod events (per actor, coalesced
//                  by OSL itself) -> update that actor. No polling anywhere.
//   SLA NG         sla_UpdateComplete heartbeat -> player + nearby NPC sweep;
//                  plus a native player poll at the MCM interval for mid-scene
//                  responsiveness (mirror of the Papyrus poll, off the VM).
//   both           TESEquipEvent on the player -> immediate under-armor
//                  refresh (replaces the Papyrus OnObjectEquipped path; snap,
//                  the Papyrus reveal tween is not reproduced natively yet).
//
// All engine work runs on the main thread via SKSE::GetTaskInterface tasks;
// sinks only classify + queue.

namespace ABM::Events
{
	// Register the mod-event + equip sinks. Call once at kDataLoaded.
	void RegisterSinks();

	// Start the (lazy) player-poll thread. Runs for the whole process; it
	// no-ops unless backend == SLA NG, the mod is enabled, and pollInterval > 0
	// in the pushed config. Call after Backend::Probe().
	void StartPollThread();

	// Wake the poll thread so a changed PollInterval takes effect now.
	void NotifyConfigChanged();
}
