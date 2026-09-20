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
		// True when the under-armor scale applies to this morph. Resolved from
		// suppress.json by ABM_Quest and pushed with the table, so the file has
		// exactly one reader and the two pipelines cannot disagree.
		bool suppressed = false;
	};

	struct Config
	{
		bool  modEnabled         = true;
		bool  ignoreMales        = true;
		bool  ignoreDead         = true;
		bool  ignoreMaleBeast    = true;
		bool  ignoreFemaleBeast  = true;
		bool  suppressUnderArmor = true;
		// True when at least one morph carries the suppressed flag -- nothing
		// to scale means the covered test isn't worth running. Derived in
		// PushSuppressFlags, not pushed.
		bool  anySuppressed      = false;
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
			// Derived from the table, so it travels with it -- the caller's
			// options block never carries a meaningful value.
			next->anySuppressed = Current()->anySuppressed;
			next->pushed = true;
			Current() = std::move(next);
		}

		// Replace the morph table, keeping the current options. Every entry
		// starts unsuppressed; PushSuppressFlags follows immediately.
		static void PushMorphTable(std::vector<MorphEntry> morphs)
		{
			std::lock_guard lock(Mutex());
			auto next = std::make_shared<Config>(*Current());
			next->morphs = std::move(morphs);
			next->anySuppressed = false;
			Current() = std::move(next);
		}

		// Apply one flag per slot of the current table.
		static void PushSuppressFlags(const std::vector<std::int32_t>& flags)
		{
			std::lock_guard lock(Mutex());
			auto next = std::make_shared<Config>(*Current());
			for (size_t i = 0; i < next->morphs.size(); ++i) {
				next->morphs[i].suppressed = i < flags.size() && flags[i] != 0;
			}
			next->anySuppressed = std::any_of(next->morphs.begin(), next->morphs.end(),
				[](const MorphEntry& morph) { return morph.suppressed; });
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
