-- Build for the optional ArousedBodyMorphs SKSE plugin (xmake 3.0+, MSVC).
-- CommonLibSSE-NG (alandtse fork, pinned v8.0.1) is vendored as a git
-- submodule at lib/commonlibsse-ng. Papyrus scripts are compiled separately
-- (../skyrimse.ppj / Pyro) -- this builds just the DLL.
--
--   cd native
--   xmake f -m release   # configure (first run compiles CommonLibSSE-NG)
--   xmake                # build; DLL is deployed to ../dist/SKSE/Plugins
--
-- Optional: set COMMONLIB_PREBUILT=1 to let NG fetch its prebuilt release
-- bundle instead of compiling from source (see lib/commonlibsse-ng/xmake.lua).

set_xmakever("3.0.0")

set_version("1.0.0") -- keep in step with ../dist/meta.ini
set_license("GPL-3.0")

set_arch("x64")
set_languages("c++23")
set_encodings("utf-8")

add_rules("mode.debug", "mode.release")

set_policy("package.requires_lock", true)

if is_mode("debug") then
    add_defines("DEBUG")
    set_optimize("none")
    set_runtimes("MTd")
else
    add_defines("NDEBUG")
    set_optimize("fastest")
    set_symbols("debug") -- keep a PDB next to the optimized DLL
    set_runtimes("MT")
    set_policy("build.optimization.lto", true)
end

includes("lib/commonlibsse-ng")

-- CommonLibSSE-NG's own xmake.lua calls set_project() too, and the last call
-- wins -- restate ours so the version resource carries this project's name.
set_project("ArousedBodyMorphs")

target("ArousedBodyMorphs", function()
    add_deps("commonlibsse-ng")
    add_rules("commonlibsse-ng.plugin", {
        name = "ArousedBodyMorphs",
        author = "crajjjj",
        description = "Event-driven arousal body morphs (native layer)",
    })

    add_files("src/*.cpp")
    add_includedirs("include", "src")
    set_pcxxheader("src/PCH.h")

    add_defines("WIN32_LEAN_AND_MEAN", "NOMINMAX", "UNICODE", "_UNICODE")

    -- Deploy ONLY the DLL to the shippable mod tree.
    after_build(function(target)
        local dist = path.join(os.projectdir(), "..", "dist", "SKSE", "Plugins")
        os.mkdir(dist)
        os.cp(target:targetfile(), dist)
    end)
end)
