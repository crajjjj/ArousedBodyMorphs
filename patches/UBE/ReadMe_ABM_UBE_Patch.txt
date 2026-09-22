Aroused BodyMorphs - UBE 2.0 Patch
==================================

Data-only patch that retargets Aroused BodyMorphs to the UBE 2.0 body
(Ultimate Body Enhancer, Nexus mod 92989). No plugin, no scripts.

What it does
------------
- morph.json: replaces the default CBBE 3BA morph table with 16 UBE 2.0
  slider names (NipplesPerkiness, AreolaErection, ClitorisErection, ...).
- IntensityPresets (Minimal/Natural/Noticeable/Exaggerated): extended with
  the UBE slider keys, so the MCM preset buttons work on the UBE table.
  The 3BA keys are still included, so presets keep working if you re-import
  a 3BA or merged morph table later.

Install
-------
1. Install as a normal mod AFTER (below) Aroused BodyMorphs, so this
   patch's JSON files win.
2. In game: MCM > Aroused BodyMorphs > Import Settings. This loads the UBE
   morph table; the sliders in the MCM now show the UBE morph names.
3. Make sure your UBE body (and any UBE outfits) are built in BodySlide
   with "Build Morphs" checked.

Notes
-----
- Only NipplesPerkiness, NippleLength, AreolaErection, ClitorisErection
  (and a few size/spread morphs in the higher tiers) ship with non-zero
  values; the rest appear as MCM sliders at 0 for your own tuning.
- "NippleLength" exists in BOTH 3BA and UBE. The patched presets use the
  UBE-tuned value for it, which is milder than the 3BA original.
- If you use UBE's *_UV_fix meshes, replace the plain slider names with
  the matching *_UV_fix names via the MCM or by editing morph.json.
- The value keys in morph.json and the presets are lowercase on purpose:
  PapyrusUtil lowercases every key it looks up, so a hand-added
  "AreolaErection" key is never read. The "morphs" list keeps the exact
  slider names.
- Mixed load orders (some actors 3BA, some UBE): add the 3BA names to
  morph.json's "morphs" list as well - a body ignores slider names it does
  not define, so a merged table is safe.

Under armor
-----------
"Suppress under armor" works unchanged with this patch: erect nipples
flatten while the chest is covered and ease back in on undress. Keep
"Under-armor scale" at 0 or above -- negative values were a 3BA-specific
trick (its NippleSize slider is inverted); on UBE a negative scale
inverts ALL morphs instead.

Requires: Aroused BodyMorphs, UBE 2.0, RaceMenu (SKEE), PapyrusUtil.
