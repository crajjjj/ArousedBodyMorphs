// Aroused BodyMorphs - BodyMorph sliders driven by SexLab Aroused arousal.
// Copyright (C) 2025-2026 crajjjj
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is built on CommonLibSSE-NG, which is GPL-3.0, and is
// distributed WITHOUT ANY WARRANTY. See the LICENSE file in the repository
// root, or <https://www.gnu.org/licenses/>.

#include "Backend.h"
#include "Events.h"
#include "MorphApplier.h"
#include "Papyrus.h"

using namespace SKSE;
using namespace SKSE::log;

namespace
{
	void InitializeLogging()
	{
		auto path = log_directory();
		if (!path) {
			stl::report_and_fail("Unable to lookup SKSE logs directory.");
		}
		*path /= PluginDeclaration::GetSingleton()->GetName();
		*path += L".log";

		std::shared_ptr<spdlog::logger> log;
		if (IsDebuggerPresent()) {
			log = std::make_shared<spdlog::logger>("Global", std::make_shared<spdlog::sinks::msvc_sink_mt>());
		} else {
			log = std::make_shared<spdlog::logger>(
				"Global", std::make_shared<spdlog::sinks::basic_file_sink_mt>(path->string(), true));
		}
		log->set_level(spdlog::level::info);
		log->flush_on(spdlog::level::trace);

		spdlog::set_default_logger(std::move(log));
		spdlog::set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
	}

	void OnMessage(MessagingInterface::Message* message)
	{
		switch (message->type) {
		case MessagingInterface::kDataLoaded:
			// Every SKSE DLL and all data is loaded -- resolve, then listen.
			ABM::Backend::Probe();
			ABM::MorphApplier::ResolveSkee();
			ABM::MorphApplier::ResolveForms();
			ABM::Events::RegisterSinks();
			ABM::Events::StartPollThread();
			logger::info("Ready. Backend: {}", ABM::Backend::Describe());
			break;
		default:
			break;
		}
	}
}

SKSEPluginLoad(const LoadInterface* skse)
{
	InitializeLogging();

	auto* plugin = PluginDeclaration::GetSingleton();
	logger::info("{} {} is loading...", plugin->GetName(), plugin->GetVersion());

	Init(skse);

	if (!GetPapyrusInterface()->Register(ABM::Papyrus::RegisterFunctions)) {
		stl::report_and_fail("Failure to register Papyrus bindings.");
	}
	if (!GetMessagingInterface()->RegisterListener(OnMessage)) {
		stl::report_and_fail("Failure to register messaging listener.");
	}

	logger::info("{} has finished loading.", plugin->GetName());
	return true;
}
