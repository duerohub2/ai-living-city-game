# ManusCC0 — Original CC0 font for games

A warm, readable UI sans made for Manus games: HUD counters, buttons, cards,
tutorials, standings, settings and compact panels. Version **1.100** includes
**Regular 400, Medium 500 and Bold 700**.

**CC0-1.0. Free for commercial use, modification, embedding and redistribution.
No attribution, copyright notice or license notice retention is required by CC0.**
No reserved font names. No embedding restrictions.

![ManusCC0 family preview](preview.png)

## The bundle

```text
manus-cc0-ui-sans/
├── README.md
├── DESIGN.md                      original construction rules
├── LICENSE                        CC0 1.0 Universal dedication
├── metadata.json
├── preview.png                    game UI overview
├── specimen.png                   all three weights at 14–48 px
├── weights.png                    family alphabet and character sheet
├── fonts/
│   ├── ManusCC0-Regular.ttf
│   ├── ManusCC0-Regular.woff2
│   ├── ManusCC0-Medium.ttf
│   ├── ManusCC0-Medium.woff2
│   ├── ManusCC0-Bold.ttf
│   └── ManusCC0-Bold.woff2
├── source/
│   ├── ManusCC0-Regular.ufo/      editable Regular source
│   ├── ManusCC0-Medium.ufo/       editable Medium source
│   ├── ManusCC0-Bold.ufo/         editable Bold source
│   ├── build_font.py               original drawings and compiler
│   ├── validate_font.py
│   ├── render_proofs.mjs
│   └── requirements.txt
├── proofs/
│   ├── preview.html
│   ├── specimen.html
│   ├── weights.html
│   ├── glyph-grid.html
│   ├── glyph-grid.png
│   ├── validation.json
│   ├── reproducibility.json
│   ├── godot-native*.png           actual engine renders
│   └── godot/                     reusable engine validation
└── reports/                       build, rendering and release evidence
```

## Original design process

The initial written rules in [DESIGN.md](DESIGN.md) established the proportions
before glyph construction. Each character begins with project-authored coordinates
in `source/build_font.py`: cubic curves, stems, bowls, terminals and accents.
Stroke expansion and overlap removal turn those drawings into closed outlines.
Editable UFO contours compile to quadratic TrueType; WOFF2 stores a compressed
web version of the same font.

The first drawings were `n o a e g t r s i l I 1 0 O R G H M`. The alphabet and
symbols extend that construction vocabulary. Spacing and optical kerning were
authored after the core shapes stabilized. The Medium and Bold styles develop
the same original geometry with deliberate increases in stroke thickness, while
preserving the family’s basic proportions and layout metrics.

The construction process accepts only the project’s own drawings and editable
sources. No external glyph outlines, coordinates, metrics, kerning, feature code,
naming records or font source assets are used. General-purpose geometry,
Unicode-naming and compilation libraries provide tools, not glyph artwork.
Proof images show actual exported font rendering, so the lettering is faithful
to the supplied binaries.

## Reading characteristics

- Large 540-unit x-height and 720-unit capitals in a 1000-unit em.
- Principal stem targets of 76, 92 and 112 units for Regular, Medium and Bold.
  Small accents and rings receive optical adjustments to protect their counters.
- Open `c`, `e` and `s`; a double-storey `a` and single-storey, hook-tailed `g`.
- Barred `I`, footed `l`, flagged and footed `1`, dotted `0`, wider undotted `O`.
- Lining numerals with equal 620-unit advances for stable HUD counters.
- Consistent character advances across Regular, Medium and Bold, so changing
  emphasis does not change text wrapping.
- Space and NBSP advance 280 units. Line metrics total 1270 units: ascender 1020,
  descender -250 and line gap 0, including headroom for accented Latin text.
- GPOS kerning; normal width; unrestricted embedding.

Use Regular for descriptions and tutorials, Medium for labels and active controls,
and Bold for headings, emphasis and victory states. These are separately drawn
exported styles; disable synthetic weights in web interfaces.

## Glyph coverage

Each weight includes **209 encoded characters and 210 glyphs including `.notdef`**:

- Every printable ASCII character, U+0020–U+007E: A–Z, a–z, 0–9, punctuation and space.
- All U+00A0–U+00FF Latin-1 supplement characters, including NBSP, accented
  letters, Æ/æ, Ð/ð, Ø/ø, Þ/þ, ß, currencies, fractions, multiplication and division.
- En/em dashes; curly single/double quotes; bullet; ellipsis; single angle quotes.
- Left/up/right/down arrows and mathematical minus.
- Check mark, multiplication X and ballot X.

Space and NBSP intentionally have no contours. The soft hyphen is encoded but
normally remains hidden until text shaping takes a discretionary line break.
The [glyph grid](proofs/glyph-grid.html) shows all encoded characters in each weight.

## Godot 4 integration and wrapping

Copy the three TTF files into `res://assets/fonts/`. Assign Regular as the Theme’s
default font. Start at 18 px for body text and inspect 14/16 px text at the actual
minimum game viewport. Apply the Medium or Bold `FontFile` explicitly to controls
that need those weights.

```gdscript
var ui_theme := Theme.new()
ui_theme.default_font = load("res://assets/fonts/ManusCC0-Regular.ttf")
ui_theme.default_font_size = 18
$UI.theme = ui_theme
$UI/VictoryLabel.add_theme_font_override(
    "font", load("res://assets/fonts/ManusCC0-Bold.ttf")
)
```

Treat text width as content-driven. A Container should give HUD counters enough
space for their largest expected values, including padding. Measure the chosen
face and actual label with `Font.get_string_size()`; do not carry over fixed
widths from an earlier template. Keep each short counter on one line, but allow
the row of counters to flow into a new row on narrow screens. Use `HFlowContainer`
for that behavior. Use `AUTOWRAP_WORD_SMART` for card descriptions and tutorial
paragraphs, and allow their containers to grow vertically. Avoid shrinking all
text to solve an isolated narrow control.

Test minimum and maximum values, localized strings, both landscape and portrait
layouts, and at least 320, 375, 768 and 1280 px viewport widths. Check labels for
clipping, overlapping controls and unintended ellipsis. The three font weights
share advance widths; changing weight alone should retain layout.

## HTML/CSS integration

Use the WOFF2 exports in browser interfaces:

```css
@font-face {
  font-family: "ManusCC0";
  src: url("ManusCC0-Regular.woff2") format("woff2");
  font-weight: 400;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: "ManusCC0";
  src: url("ManusCC0-Medium.woff2") format("woff2");
  font-weight: 500;
  font-style: normal;
  font-display: swap;
}
@font-face {
  font-family: "ManusCC0";
  src: url("ManusCC0-Bold.woff2") format("woff2");
  font-weight: 700;
  font-style: normal;
  font-display: swap;
}
.game-ui {
  font-family: "ManusCC0", sans-serif;
  font-synthesis: none;
  line-height: 1.4;
}
.hud { display: flex; flex-wrap: wrap; gap: 0.75rem; }
.hud-counter { white-space: nowrap; flex: 0 0 auto; }
.card-copy { min-width: 0; overflow-wrap: anywhere; }
```

Reserve enough room for the real text before fonts finish loading. Prefer intrinsic
widths, wrapping flex/grid layouts and an explicit button padding budget. Do not
use fixed heights on multiline body copy.

## Editing and rebuilding

The UFO sources are editable in a UFO-capable font editor. `build_font.py` is the
parametric drawing master; a normal build regenerates the sources and all exports.
Use `--from-ufo` to compile manual source edits without regenerating the drawings.
The default build covers all faces; `--style Regular`, `--style Medium` or
`--style Bold` selects an individual face.
From this package folder:

```sh
python3 -m venv .venv
.venv/bin/pip install -r source/requirements.txt
.venv/bin/python source/build_font.py
.venv/bin/python source/validate_font.py
.venv/bin/python source/build_font.py --from-ufo
```

UFO `features.fea` supplies the compiler’s OpenType feature code; keep it in sync
with any manual kerning edits. [Reproducibility results](proofs/reproducibility.json)
record release rebuild checks.

Open the reusable HTML proofs directly, or serve this directory locally. To
regenerate the PNGs, use Node with Playwright and a Chrome installation:

```sh
FONT_PROOF_PYTHON=.venv/bin/python node source/render_proofs.mjs
```

Set `PLAYWRIGHT_MODULE` to the absolute module entry path if needed. The renderer
uses only bundled ManusCC0 fonts, launches a muted browser and closes it on completion.
`--write-only` regenerates the HTML without rendering.

## Validation and limitations

[Font validation](proofs/validation.json) covers required characters, naming and
style flags, equal numeral widths, distinct ambiguity glyphs, contours, metric
bounds, editable-source agreement, TTF/WOFF2 equivalence, shaping and rendering.
[Browser proofs](reports/proof-rendering.json) check the actual three weights at
**14, 16, 18, 24, 32 and 48 px** on light and dark backgrounds with synthesis disabled.

[Native Godot validation](reports/godot-validation.json) checks all three TTFs:
direct loading, editor import, character mapping, text shaping, numeral advances
and cross-weight layout consistency. Each face is rendered with fallback disabled.
A reusable silent test fixture is included in [proofs/godot](proofs/godot/README.md).
Native-engine validation does not establish browser-export or device-specific results.

The release has no italic or variable style, per-glyph TrueType hint instructions,
proportional-digit alternate, ligatures or combining-mark positioning. It does not
cover Greek, Cyrillic, CJK, emoji or the full Latin Extended repertoire. Normalize
supported accented Latin to NFC and supply suitable script coverage in multilingual
games. Kerning is targeted rather than exhaustive. Small-text appearance depends
on pixel density, scaling, antialiasing and rasterizer.

## Public-domain dedication

To the extent possible under law, all copyright and related or neighboring rights
held, if any, in the original ManusCC0 font, drawings, build/validation code and
original documentation are dedicated to the public domain under **CC0 1.0 Universal**.
The dedication applies to original contributions, regardless of whether particular
AI-assisted elements attract copyright in a given jurisdiction. [LICENSE](LICENSE)
contains the dedication and fallback license.

CC0 imposes no attribution or notice-retention conditions on downstream games,
editable projects or reusable templates. The legal text is included as provenance;
CC0 does not require you to reproduce it in your game. CC0 does not grant trademark
or patent rights. Build dependencies retain their own licenses and are not bundled
into the font files.
