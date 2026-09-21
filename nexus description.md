[size=4][b]Aroused BodyMorphs[/b][/size]

Nipples, areolas and other morphs in step with Aroused mods arousal. 0 arousal = no morph, 100 = the full value you set in the MCM, linear in between. Works on the player and on nearby NPCs.

The default set targets CBBE 3BA: 23 sliders covering the nipple set, areola, and the 3BA labia/vagina/clit sliders. Pick one of four intensity presets and you are done, or tune every slider yourself. Custom morphs can be added in the morph json.

[size=3][b]Requirements[/b][/size]
[list]
[*]SKSE64 and SkyUI[/*]
[*]RaceMenu (SKEE / NiOverride), for the BodyMorph API[/*]
[*]PapyrusUtil[/*]
[*]SexLab Aroused, any flavour: SexLab Aroused NG / SLO Aroused NG (recommended), OSL Aroused, or legacy SLAX / SSELoose / eXtended[/*]
[*]A 3BA-compatible body built in BodySlide [b]with "Build Morphs" checked[/b]. Without morph data nothing is visible in game.[/*]
[*]Optional: Advanced Nudity Detection, for better "under armor" detection on bikinis and skimpy tops[/*]
[/list]
[b]SexLab itself is not required.[/b] The masters are Skyrim, Update and SexLabAroused only, so OStim-only setups load fine.

[size=3][b]Features[/b][/size]
[list]
[*][b]Intensity presets:[/b] Minimal, Natural, Noticeable, Exaggerated. Natural is the install default.[/*]
[*][b]Per-morph sliders[/b] grouped by area (Nipples / Areolas / Vagina / Other), in 0.01 steps.[/*]
[*][b]Under-armor suppression:[/b] morphs flatten while the chest is covered so nothing clips through tops, then ease back in over about a second when the top comes off.[/*]
[*][b]Actor filters:[/b] ignore males, dead actors, male or female creatures. NPC scan radius is adjustable, and 0 means "only me".[/*]
[*][b]Master switch:[/b] turning the mod off clears every morph it owns and goes fully dormant. Your tuning is kept.[/*]
[*][b]SKSE plugin:[/b] with SLO Aroused NG or OSL Aroused, updates become event-driven and all morph writes go through SKEE directly, for far lower script load. Delete the DLL and the Papyrus version runs instead.[/*]
[*][b]Import / Export[/b] all settings and the morph table as JSON. Custom morph lists for other bodies can be imported the same way.[/*]
[/list]

[size=3][b]Installation[/b][/size]
Install with a mod manager and build your body in BodySlide with morphs enabled. Everything else is configured in the MCM, with no ini editing. Natural preset by default.

[size=3][b]Notes[/b][/size]
[list]
[*]NPCs update on SexLab Aroused's scan tick, roughly every 2 minutes by default. Your own body refreshes every few seconds, adjustable in the MCM.[/*]
[/list]
[size=3][b]Credits[/b][/size]
Inspired by the ArousedNips (TanookiTamaTachi) family of mods and their community forks.
Source and issue tracker: [url=https://github.com/crajjjj/ArousedBodyMorphs]github.com/crajjjj/ArousedBodyMorphs[/url]

[size=3][b]License[/b][/size]
Aroused BodyMorphs is free software, licensed under the [url=https://www.gnu.org/licenses/gpl-3.0.html][b]GNU General Public License v3.0[/b][/url] (or, at your option, any later version), and comes with [b]no warranty[/b]. The SKSE plugin is built on [url=https://github.com/alandtse/CommonLibSSE-NG]CommonLibSSE-NG[/url], which is GPL-3.0, so this mod is distributed under the same terms.

The complete corresponding source is in the GitHub repository above. The download also ships the full, unmodified license text as [i]LICENSE.txt[/i] and the Papyrus sources under [i]source\scripts[/i]. In line with the GPL, you are free to use, modify and redistribute this mod, including modified versions, as long as you keep it under the GPL-3.0 and credit the original work.
