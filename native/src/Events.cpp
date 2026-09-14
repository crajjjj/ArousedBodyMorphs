#include "Events.h"

#include "Backend.h"
#include "MorphApplier.h"
#include "Settings.h"

namespace ABM::Events
{
	namespace
	{
		// Coalesce heartbeat sweeps: drop the event if one is already queued.
		std::atomic<bool> g_sweepPending{ false };

		// Same for equip refreshes: a redress fires one event per item, and
		// one queued task re-reads the final worn state anyway.
		std::atomic<bool> g_equipRefreshPending{ false };

		// condition_variable_ANY so the jthread's stop_token can interrupt the
		// wait. A plain condition_variable never sees the stop request, leaving
		// the destructor's join blocked for the rest of the interval (up to
		// 60s) at shutdown.
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
		// live in UpdateActor, so this only bounds the sweep spatially; its
		// unchanged-value probe then skips every bystander already at target.
		// Main thread only.
		void SweepNearby()
		{
			auto player = RE::PlayerCharacter::GetSingleton();
			if (!player) {
				return;
			}
			MorphApplier::UpdateActor(player);

			auto cfg = Settings::Snapshot();
			if (cfg->scanRadius <= 0.0f) {
				return;  // NPC updates switched off in the MCM -- player only
			}
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
					// sender is the actor, but the payload float is OSL's
					// exposure -- re-read composite arousal in the task.
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
				// Snap to the new covered/bare state; an outfit-swap burst
				// collapses to one refresh. TODO: reproduce the Papyrus ~1s
				// reveal ease for the unequip direction.
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
				// Idle cadence while inactive, the pushed interval while
				// active. Wakes early on a config push (flagged under the
				// mutex so it can't be lost) or on the stop request.
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
