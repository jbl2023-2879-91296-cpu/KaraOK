# Recommendation quality findings — 2026-10-25

Before algorithm changes, technician-mode initial corrections were capped at 10% of the amplifier range (2 units on −10…+10), with verification capped at 5% (1 unit). Corrections targeted the acceptable interval edge, so rounding frequently produced one-unit changes.

Genre targets do differ: bass acceptable ranges are Pop 79.79–93.22, R&B 66.67–87.35, Rock 88.12–94.78.

Existing fixture recordings, initial bass/treble changes on −10…+10:

| Recording | Pop | R&B | Rock |
| --- | --- | --- | --- |
| pop-01 | +2 / +1 | 0 / +1 | +2 / 0 |
| pop-10 | −1 / 0 | −2 / 0 | 0 / 0 |
| pop-11 | 0 / −1 | −1 / −1 | +2 / −1 |

Proposed change: out-of-range technician tone controls target the genre median, with caps of 15% initial and 7.5% verification. Preserve in-range controls, existing volume limits, and clipping/distortion guards. These are recording-fixture results; audible improvement and speaker safety still require testing on actual hardware at a conservative listening level.

## Implemented result

The engine now targets the median only when a tone measurement is outside its genre range. Initial tone corrections are capped at 15% of the physical range; verification corrections at 7.5%. Volume retains its 10% / 5% limits and uses its own configured range and step. Existing clipping and excessive-distortion signals block boosts.

Recalculated from neutral positions on −10…+10, step 1 (Bass / Treble deltas):

| Recording | Pop | R&B | Rock |
| --- | --- | --- | --- |
| pop-01 | +3 / +2 | 0 / +1 | +3 / 0 |
| pop-10 | −2 / 0 | −3 / 0 | 0 / 0 |
| pop-11 | 0 / −2 | −2 / −3 | +3 / −3 |

Regression checks cover every fixture recording across all three genres, initial and verification passes, multiple hardware ranges, boundaries, and clipping/distortion. An independent −80…0 dB volume scale at −60 dB recommends −52 dB initially or −56 dB during verification for a sufficiently quiet recording, and holds −60 dB when a distortion guard is active.

These numbers demonstrate stronger and genre-dependent corrections. They do not establish audible improvement or a safe listening level on an uncharacterized amplifier. Physical listening tests remain outstanding; the engine cannot guarantee speaker protection from recording measurements alone.
