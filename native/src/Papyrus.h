#pragma once

namespace ABM::Papyrus
{
	// Bind the ABM_Native script functions. Passed to
	// SKSE::GetPapyrusInterface()->Register.
	bool RegisterFunctions(RE::BSScript::IVirtualMachine* vm);
}
