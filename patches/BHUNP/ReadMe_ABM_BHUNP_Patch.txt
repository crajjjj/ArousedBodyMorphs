Aroused BodyMorphs - BHUNP Patch
================================

Data-only patch that retargets Aroused BodyMorphs to the BHUNP (UUNP Next
Generation) body. No plugin, no scripts. Slider names verified against the
official "BHUNP Skyrim Vanilla Outfits" BodySlide projects.

What it does
------------
- morph.json: replaces the default CBBE 3BA morph table with 20 BHUNP
  slider names (NippleErection, NipplePerkiness, NipplePuffyAreola,
  ClitorisErection, PussyMajora, ...).
- IntensityPresets (Minimal/Natural/Noticeable/Exaggerated): extended with
  the BHUNP slider keys. The 3BA keys are still included, so presets keep
  working if you re-import a 3BA or merged morph table later.

Install
-------
1. Install as a normal mod AFTER (below) Aroused BodyMorphs, so this
   patch's JSON files win.
2. In game: MCM > Aroused BodyMorphs > Import Settings. This loads the
   BHUNP morph table; the MCM sliders now show the BHUNP morph names.
3. Make sure your BHUNP body and outfits are built in BodySlide with
   "Build Morphs" checked.

Notes
-----
- Non-zero out of the box: NippleErection, NipplePerkiness, NippleLength,
  NippleSize, NipplePuffyAreola, ClitorisErection, Clit, PussyMajora.
  The rest appear as MCM sliders at 0 for your own tuning.
- BHUNP shares several slider names with CBBE 3BA (NippleSize,
  NippleLength, NipplePerkiness, Clit, NipplePerkManga). Slider names are
  case-insensitive, but the value keys in the JSON files must stay
  lowercase: PapyrusUtil lowercases every key it looks up, so a hand-added
  "NippleSize" key is never read. The patched presets use BHUNP-tuned
  values for the shared names; in particular NippleSize is now POSITIVE
  (bigger with arousal), while the 3BA original used negative values.
  Pure-3BA setups should not use this patch's presets.
- Mixed load orders (some actors 3BA, some BHUNP): add the 3BA names to
  morph.json's "morphs" list as well - a body ignores slider names it
  does not define, so a merged table is safe. Shared names will drive
  both bodies with the same value.

Under armor
-----------
"Suppress under armor" works unchanged with this patch: erect nipples
flatten while the chest is covered and ease back in on undress. Keep
"Under-armor scale" at 0 or above -- negative values were a 3BA-specific
trick (its NippleSize slider is inverted); on BHUNP (positive NippleSize)
a negative scale inverts ALL morphs instead.

Requires: Aroused BodyMorphs, a BHUNP body, RaceMenu (SKEE), PapyrusUtil.
