#pragma once

// Config mirrored from Papyrus (PushConfigToNative). The MCM stays the source
// of truth; this is a read-mostly copy. Readers take an immutable snapshot
// (shared_ptr swap) so sinks and the poll thread never hold a lock across
// engine calls.

namespace ABM
{
	struct MorphEntry
	{
		std::string name;
		float       maxValue = 0.0f;
	};

	struct Config
	{
		bool  modEnabled         = true;
		bool  ignoreMales        = true;
		bool  ignoreDead         = true;
		bool  ignoreMaleBeast    = true;
		bool  ignoreFemaleBeast  = true;
		bool  suppressUnderArmor = true;
		float underArmorScale    = 0.0f;
		float pollInterval       = 5.0f;   // seconds; 0 disables the SLA NG player poll
		float scanRadius         = 1000.0f;
		bool  debugMode          = false;
		bool  pushed             = false;  // false until Papyrus pushed at least once

		std::vector<MorphEntry> morphs;
	};

	class Settings
	{
	public:
		static std::shared_ptr<const Config> Snapshot()
		{
			std::lock_guard lock(Mutex());
			return Current();
		}

		// Replace the option block, keeping the current morph table.
		static void PushConfig(const Config& options)
		{
			std::lock_guard lock(Mutex());
			auto next = std::make_shared<Config>(options);
			next->morphs = Current()->morphs;
			next->pushed = true;
			Current() = std::move(next);
		}

		// Replace the morph table, keeping the current options.
		static void PushMorphTable(std::vector<MorphEntry> morphs)
		{
			std::lock_guard lock(Mutex());
			auto next = std::make_shared<Config>(*Current());
			next->morphs = std::move(morphs);
			Current() = std::move(next);
		}

	private:
		static std::mutex& Mutex()
		{
			static std::mutex mutex;
			return mutex;
		}

		static std::shared_ptr<const Config>& Current()
		{
			static std::shared_ptr<const Config> current = std::make_shared<Config>();
			return current;
		}
	};
}
