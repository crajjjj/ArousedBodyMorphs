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
			// Every SKSE DLL (arousal backends, skee) is loaded and data is in;
			// resolve everything, then start listening.
			ABM::Backend::Probe();
			ABM::MorphApplier::ResolveSkee();
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
