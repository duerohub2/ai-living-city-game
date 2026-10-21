# Runtime font sources

The current `assets.lock.json` bundles the following fonts:

| Font file | License | Bundled notice |
| --- | --- | --- |
| `ManusCC0-Bold.woff2` | CC0-1.0 | [ManusCC0-CC0.txt](ManusCC0-CC0.txt) |
| `NotoSansSC-VF.subset.woff2` | OFL-1.1 | [NotoSansSC-OFL.txt](NotoSansSC-OFL.txt) |
| `Rubik-VF.subset.woff2` | OFL-1.1 | [Rubik-OFL.txt](Rubik-OFL.txt) |
| `display/ZCOOLQingKeHuangYou-Regular.subset.woff2` | OFL-1.1 | [ZCOOLQingKeHuangYou-OFL.txt](display/ZCOOLQingKeHuangYou-OFL.txt) |

ManusCC0 output fonts are full, unmodified files. [Replacement evidence](../../../docs/provenance/fonts/replacement-fonts.json) records their reviewed sources, hashes and sizes. The other active families retain their adjacent SIL Open Font License notices. Keep those notices when redistributing the fonts.

[Historical font evidence](../../../docs/provenance/historical-font-licenses/index.json) preserves replaced families' notices and original paths outside the runtime font directories. Those replaced binaries are not bundled in this revision.

Noto Sans SC (`NotoSansSC-VF.subset.woff2`, variable weight) supplies the
common Simplified Chinese glyph fallback after the template's body font. Its
hash and size are in `assets.lock.json` and `runtime-cjk.json`. It covers the
shared common repertoire, including player input, rather than only current UI
copy. Rare characters outside that repertoire remain unsupported.

Use `python3 tools/install_cjk_font.py --check` to verify the pinned runtime
font and its license. Loader fonts are separate lightweight subsets of the same
approved family. Runtime imports disable system fallback; web exports bundle the font.
