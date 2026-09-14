#include "Events.h"

#include "Backend.h"
#include "MorphApplier.h"
#include "Settings.h"

namespace ABM::Events
{
	namespace
	{
		// Coalesce heartbeat sweeps: if one is already queued, drop the event
		// (same pattern OSL Aroused uses for its AND refresh bursts).
		std::atomic<bool> g_sweepPending{ false };

		// Coalesce player equip refreshes the same way: a redress fires one
		// TESEquipEvent per item in the same frame(s); one queued task
		// re-reads the final worn state, so the rest add nothing.
		std::atomic<bool> g_equipRefreshPending{ false };

		// condition_variable_any so the jthread's stop_token can interrupt
		// the wait -- a plain condition_variable never sees the stop request,
		// which would leave the destructor's join blocked for the remainder
		// of the interval (user-settable up to 60s) at shutdown.
		std::condition_variable_any g_pollCv;
		std::mutex                  g_pollMutex;
		bool                        g_configDirty = false;  // guarded by g_pollMutex

		void UpdatePlayerTask()
		{
			SKSE::GetTaskInterface()->AddTask([]() {
				if (auto player = RE::PlayerCharacter::GetSingleton()) {
					MorphApplier::UpdateActor(player);
				}
			});
		}

		// Player + every high-processed NPC within scanRadius. Actor filters
		// (sex/dead/creature) live in MorphApplier::UpdateActor, so this only
		// bounds the sweep spatially; UpdateActor's unchanged-value probe then
		// skips the write for actors already at their target values -- in
		// particular every never-aroused bystander. Main thread only.
		void SweepNearby()
		{
			auto player = RE::PlayerCharacter::GetSingleton();
			if (!player) {
				return;
			}
			MorphApplier::UpdateActor(player);

			auto cfg = Settings::Snapshot();
			const float radiusSq = cfg->scanRadius * cfg->scanRadius;
			auto processLists = RE::ProcessLists::GetSingleton();
			if (!processLists) {
				return;
			}
			const auto playerPos = player->GetPosition();
			for (auto& handle : processLists->highActorHandles) {
				auto actorPtr = handle.get();
				auto actor = actorPtr.get();
				if (!actor || actor == player || actor->IsDisabled() || actor->IsChild()) {
					continue;
				}
				if (playerPos.GetSquaredDistance(actor->GetPosition()) > radiusSq) {
					continue;
				}
				MorphApplier::UpdateActor(actor);
			}
		}

		class ModCallbackSink : public RE::BSTEventSink<SKSE::ModCallbackEvent>
		{
		public:
			static ModCallbackSink* GetSingleton()
			{
				static ModCallbackSink sink;
				return &sink;
			}

			RE::BSEventNotifyControl ProcessEvent(const SKSE::ModCallbackEvent* event,
				RE::BSTEventSource<SKSE::ModCallbackEvent>*) override
			{
				if (!event || event->eventName.empty()) {
					return RE::BSEventNotifyControl::kContinue;
				}
				const auto kind = Backend::GetKind();
				const char* name = event->eventName.c_str();

				if (kind == Backend::Kind::kOsl &&
					std::strcmp(name, "OSLA_ActorArousalUpdated") == 0) {
					// sender is the actor; the payload float is OSL's exposure,
					// so re-read the composite arousal through GetArousalExt in
					// the task instead of trusting numArg semantics.
					auto actor = event->sender ? event->sender->As<RE::Actor>() : nullptr;
					if (actor) {
						RE::ActorHandle handle = actor->GetHandle();
						SKSE::GetTaskInterface()->AddTask([handle]() {
							if (auto actorPtr = handle.get()) {
								MorphApplier::UpdateActor(actorPtr.get());
							}
						});
					}
					return RE::BSEventNotifyControl::kContinue;
				}

				if (kind == Backend::Kind::kSlaNg &&
					std::strcmp(name, "sla_UpdateComplete") == 0) {
					if (!g_sweepPending.exchange(true)) {
						SKSE::GetTaskInterface()->AddTask([]() {
							g_sweepPending.store(false);
							SweepNearby();
						});
					}
					return RE::BSEventNotifyControl::kContinue;
				}

				return RE::BSEventNotifyControl::kContinue;
			}
		};

		class EquipSink : public RE::BSTEventSink<RE::TESEquipEvent>
		{
		public:
			static EquipSink* GetSingleton()
			{
				static EquipSink sink;
				return &sink;
			}

			RE::BSEventNotifyControl ProcessEvent(const RE::TESEquipEvent* event,
				RE::BSTEventSource<RE::TESEquipEvent>*) override
			{
				if (!event || !event->actor || !event->actor->IsPlayerRef()) {
					return RE::BSEventNotifyControl::kContinue;
				}
				if (Backend::GetKind() == Backend::Kind::kNone) {
					return RE::BSEventNotifyControl::kContinue;
				}
				auto cfg = Settings::Snapshot();
				if (!cfg->modEnabled || !cfg->suppressUnderArmor) {
					return RE::BSEventNotifyControl::kContinue;
				}
				auto form = RE::TESForm::LookupByID(event->baseObject);
				if (!form || !form->As<RE::TESObjectARMO>()) {
					return RE::BSEventNotifyControl::kContinue;
				}
				// Snap to the new covered/bare state; the queued task reads
				// the final worn state, so an outfit-swap burst collapses to
				// one refresh. TODO: reproduce the Papyrus ~1s reveal ease
				// for the unequip direction.
				if (!g_equipRefreshPending.exchange(true)) {
					SKSE::GetTaskInterface()->AddTask([]() {
						g_equipRefreshPending.store(false);
						if (auto player = RE::PlayerCharacter::GetSingleton()) {
							MorphApplier::UpdateActor(player);
						}
					});
				}
				return RE::BSEventNotifyControl::kContinue;
			}
		};

		void PollLoop(std::stop_token stop)
		{
			std::unique_lock lock(g_pollMutex);
			while (!stop.stop_requested()) {
				auto cfg = Settings::Snapshot();
				const bool active = Backend::GetKind() == Backend::Kind::kSlaNg &&
				                    cfg->pushed && cfg->modEnabled && cfg->pollInterval > 0.0f;
				// Idle wakeup cadence while inactive; the pushed interval while
				// active. Wakes early on a config push (g_configDirty, set +
				// notified under the mutex so the wakeup can't be lost) or on
				// the jthread's stop request at shutdown.
				const auto wait = active ?
					std::chrono::milliseconds(static_cast<long long>(cfg->pollInterval * 1000.0f)) :
					std::chrono::milliseconds(2000);
				g_pollCv.wait_for(lock, stop, wait, [] { return g_configDirty; });
				g_configDirty = false;
				if (stop.stop_requested()) {
					return;
				}
				if (active) {
					UpdatePlayerTask();
				}
			}
		}

		std::jthread g_pollThread;
	}

	void RegisterSinks()
	{
		if (auto source = SKSE::GetModCallbackEventSource()) {
			source->AddEventSink(ModCallbackSink::GetSingleton());
			logger::info("Mod-event sink registered");
		} else {
			logger::error("Failed to get ModCallbackEvent source");
		}
		if (auto holder = RE::ScriptEventSourceHolder::GetSingleton()) {
			holder->AddEventSink(EquipSink::GetSingleton());
			logger::info("Equip sink registered");
		} else {
			logger::error("Failed to get ScriptEventSourceHolder");
		}
	}

	void StartPollThread()
	{
		if (!g_pollThread.joinable()) {
			g_pollThread = std::jthread(PollLoop);
		}
	}

	void NotifyConfigChanged()
	{
		{
			std::lock_guard lock(g_pollMutex);
			g_configDirty = true;
		}
		g_pollCv.notify_all();
	}
}
