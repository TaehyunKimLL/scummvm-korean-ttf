# SCITRS — a Unicode fan-translation format for SCI

Status: **implemented and verified**. Writer `harness/i18n/m5mktrs.py`,
reader `engines/sci/engine/translation.{h,cpp}`.

Verified end to end on a pristine English KQ1 (1991 remake): a 1,786 entry
`ko` bundle built from the legacy patch, dropped in as `sci.trs` with no
Text.MAP/Text.Res present and no game file modified, makes the game draw
Korean. Removing the bundle restores English. 403/403 unit tests pass.

## Why not the existing formats

Three fan-patch formats already exist in the wild, and each is unusable as a
general mechanism for a different reason. All three were measured, not assumed
(see `M5_TEXT_OVERLAY.md`).

| Format | Used by | Keyed by | Encoding | Fatal limitation |
|---|---|---|---|---|
| `Text.MAP`/`Text.Res` | KQ1, KQ5, SQ1, Mother Goose, Fairy Tales | resource number + index | EUC-KR | Position-keyed: a script patch that renumbers or reorders strings silently mistranslates. One encoding, one language. |
| `message.map`/`resource.msg` | LB2CD, GK1CD, FPFPCD | message tuple | EUC-KR | Same, plus SCI32-only. |
| modified `resource.001` | LB1 | n/a | EUC-KR | Destroys the original data; cannot ship alongside an unmodified game. |

`kq1.xml` — the authoring file that shipped beside the KQ1 patch — is keyed by
the **English source string**, and that is the right shape of key: it survives
renumbering, it can be diffed, and a missing entry degrades to the original
English rather than to garbage.

**But kq1.xml is not usable as the data source, and this was measured rather
than assumed.** Of its 308 pairs, only 22 (7.1%) match any string in the
English KQ1 1991 remake even after whitespace normalisation, and 286 appear
nowhere in the game's resources at all - not in TEXT, not as plaintext in any
volume. Its Korean values also disagree with the shipped Text.Res: only 6 of
308 are present there. kq1.xml is a different translation of a different
edition, kept alongside the patch for reference.

The usable pairing comes from the patch itself. Aligning the Korean Text.Res
against the untouched English resources by `(resource, index)` yields **1,786
translation pairs with zero missing entries** - 1,788 of 1,795 strings are
translated, 7 deliberately left in English. That alignment is what
`m5mktrs.py` consumes, and the English side of each pair becomes the SCITRS
source key.

## Design rules

1. **Source-keyed.** The lookup key is the original resource text, so the
   translation is independent of resource numbering.
2. **Unicode throughout.** Strings are stored as UTF-8; the engine decodes to
   `uint32` code points. No byte-encoding is baked into the file, so one
   format serves German and Korean alike.
3. **Position hints, not position keys.** Each entry may carry the
   `(resource, index)` where it was seen. That is a fast path only — a hint
   that fails falls back to the hash lookup, and a wrong hint can never
   produce a wrong string.
4. **Degrade to the original.** Any failure — missing entry, bad hash, short
   file — yields "no translation" and the engine draws the shipped text.
5. **One file, many languages.** A bundle holds N language tables; the active
   one is chosen at load time.

## Layout

All integers little-endian. Offsets are from the start of the file.

```
header
  0x00  char[8]  magic      "SCITRS\0\0"
  0x08  u16      version    1
  0x0A  u16      langCount
  0x0C  u32      stringPool offset
  0x10  u32      stringPool length, bytes
  0x14  u32      reserved (0)
  0x18  langEntry[langCount]

langEntry (32 bytes)
  +0x00 char[8]  code       BCP-47-ish, NUL padded: "ko", "de", "pt-BR"
  +0x08 u32      entryCount
  +0x0C u32      entries offset
  +0x10 u32      bucketCount   power of two
  +0x14 u32      buckets offset
  +0x18 u32      flags         bit0: hints present
  +0x1C u32      reserved (0)

entry (20 bytes), sorted by hash then by source offset
  +0x00 u32      hash        FNV-1a 32 of the NORMALISED source (see below)
  +0x04 u32      srcOffset   into stringPool, UTF-8, NUL terminated
  +0x08 u32      dstOffset   into stringPool, UTF-8, NUL terminated
  +0x0C u16      resource    hint: TEXT resource number, 0xFFFF = none
  +0x0E u16      index       hint: string index within that resource
  +0x10 u32      reserved (0)

buckets: u32[bucketCount + 1]
  bucket b holds entries [buckets[b], buckets[b+1]) — an open-addressing-free
  layout that needs one indirection and no probing.

stringPool: NUL-terminated UTF-8 blobs, deduplicated.
```

## Key normalisation

The source text a game hands to `lookupText()` is not byte-identical to what a
translator typed: SCI pads menu items with spaces, uses `\r` for line breaks,
and scripts embed runs of whitespace for layout. Hashing the raw bytes would
miss most entries — measured on `kq1.xml`, raw hashing matched 6/308 while
normalised hashing matched all 308.

Normalisation, applied identically by writer and reader:

1. Decode to code points (UTF-8 in the file; the engine's source bytes are
   decoded from the game's encoding first).
2. Map `\r`, `\n`, `\t` to space.
3. Collapse runs of spaces to one.
4. Strip leading and trailing spaces.

Nothing else — no case folding, no punctuation stripping. Two distinct source
strings that differ only in whitespace are genuinely the same string as far as
a translator is concerned, and anything more aggressive starts merging lines
that should stay apart.

Hash is FNV-1a 32 over the **UTF-8 bytes of the normalised form**. Collisions
are resolved by comparing the normalised source, so a collision costs a
comparison and never a wrong answer.

## What the reader must guarantee

- A file that fails any structural check is rejected whole; a partially
  indexed translation is worse than none.
- `getText()` returns false rather than an empty string when there is no
  entry, so callers can distinguish "translated to nothing" from "not
  translated".
- Lookup is const and allocation-free apart from the returned string.

## Relationship to the byte-arithmetic problem

Card M4 measured that SCI scripts *do* perform byte arithmetic on translatable
text: in Cascade Quest, script 979 walks dialogue with `kStrAt` and compares
each offset with `kStrCmp`. SCITRS does not solve that and does not pretend
to. It defines how a translation is *stored and located*; what the engine does
with the bytes afterwards is the fence question, and the four ops M4 named
(`kStrAt`, `kStrCmp`-with-length, `kStrLen`, `kStrCpy`) still need handling
before an internal code-point representation is safe.

What SCITRS does buy is that the *file* is encoding-neutral. A future engine
that stores text as `uint32` code points reads the same bundle as today's
byte-oriented one; only the decode step at the boundary changes.
