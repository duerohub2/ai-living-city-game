# ManusCC0 — original construction rules

The initial Regular construction brief was recorded before glyph drawing on
2026-09-10. The three-weight family extension was added on the same date for
version 1.100. These rules describe the authored design rather than promise
exclusive ownership of conventional alphabet structures.

## Purpose

A Latin UI sans for game HUDs, controls, tutorials, cards and standings. Favor
legibility, calm rhythm and warmth. Regular supports sustained reading, Medium
gives controls stronger emphasis, and Bold anchors headings and game-state messages.

## Construction boundary

The drawing/build process accepts only original project drawings and editable
sources. All control points, widths, component placements and kerning values are
authored for ManusCC0. External glyph outlines, coordinates, tables, features,
naming records, source files and build scripts are excluded from the process.

## Original geometry

- Em: 1000 units. Baseline: 0. Flat x-height: 540. Flat cap height: 720.
- Ascending lowercase stems: 750. Descending forms reach approximately -210.
- Rounded forms overshoot the baseline and height by 10 units.
- Principal stem targets: Regular 76, Medium 92 and Bold 112 units. Small rings
  and accents receive gentler optical growth; the degree sign widens to retain
  its counter at small rendered sizes.
- Shared line metrics: ascender 1020, descender -250, line gap 0. The extra
  headroom accommodates antialiased heavy accented capitals at small sizes.
- Curves use individually authored cubic Beziers. Bowls have a slightly upright
  oval silhouette; shoulders are flatter at the crown than a perfect circle.
- Predominantly flat terminals and rounded joins where needed.
- Double-storey `a`: compact lower bowl with an open upper entry.
- Single-storey `g`: open descending hook.
- `e`: a generous right aperture and level crossbar; `c`: angled open ends.
- `l`: a short curved foot; `I`: horizontal head and foot bars.
- `1`: angled flag with baseline foot; `0`: narrow oval and central dot;
  `O`: wider, undotted oval. Every numeral advances 620 units.
- `R`: diagonal leg leaving the bowl near the middle; `G`: open bowl and short
  interior shelf. `M`: diagonals with a high central vertex.
- Intentional variation in lowercase widths; monospacing applies only to digits.
- Space and NBSP: 280 units. Tabular numerals are the default.
- The three styles share glyph advances, kerning and line metrics so emphasis
  changes stroke density without disrupting text layout.

## Drawing and finishing order

1. Draw `n o a e g t r s i l I 1 0 O R G H M` from the authored proportions.
2. Extend the alphabet with original stem and bowl construction helpers.
3. Draw punctuation, arithmetic signs, arrows and check/cross UI symbols.
4. Build Latin-1 from the original base glyphs and accents.
5. Resolve overlaps into closed contours and export editable UFO sources.
6. Tune sidebearings and selected optical kerning after stabilizing shapes.
7. Extend the geometry to Medium and Bold with shared layout metrics.
8. Compile TrueType and WOFF2; verify their naming, contours and agreement.
9. Render each weight at 14, 16, 18, 24, 32 and 48 px on dark and light surfaces.
10. Check game strings, native shaping and stable widths across the family.

## Release bar

Each face must load under the ManusCC0 family with its correct style and numeric
weight, cover all promised characters, distinguish ambiguous glyphs, and retain
steady-width counters. Medium and Bold must be separate outline exports, with no
runtime synthetic emboldening. Deliver editable sources, reproducible build tools,
real rendering proofs and the CC0 dedication together. Document rendering and
language-coverage limitations accurately.
