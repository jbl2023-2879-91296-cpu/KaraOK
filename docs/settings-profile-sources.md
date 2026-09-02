# Genre audio profile sources

This report is generated deterministically by KaraOK's genre profile derivation CLI.
Every enabled target comes from the exact five KaraOK analyzer measurements.

## Reproducibility

- Profile version: `2026.09.1`
- Generator version: `1.0.0`
- Generated at: `2026-09-02T00:00:00Z`
- Source manifest SHA-256: `642c6d23d4e2388f80ad5f324a31223054900f2a4d7c6639edb76d6b5e5be74d`
- Artifact checksum: `8b87b9f1106bab8dab4978e4590e84c9bb294400a0d60ce5263e196f44701b61`
- Calculation: NumPy linear p25/median/p75; robust_scale=max(p75-p25, abs(median)*0.05, 1e-9)

## Genre availability

| Genre | Status | Instrumental evidence | Compatible recordings |
| --- | --- | --- | ---: |
| rock | Enabled | Unverified instrumental status | 5 |
| pop | Enabled | Unverified instrumental status | 5 |
| ballad | Disabled | N/A | 0 |
| hip-hop | Enabled | Unverified instrumental status | 5 |
| classical | Disabled | N/A | 0 |
| r&b | Disabled | N/A | 0 |
| general | Disabled | N/A | 0 |

Enabled genres: rock, pop, hip-hop.
Disabled genres: ballad, classical, r&b, general.

## Source provenance

| Source | Version | Individual license | Citation | Recordings |
| --- | --- | --- | --- | ---: |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution | <https://github.com/mdeff/fma> | 3 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution 2.0 UK: England | <https://github.com/mdeff/fma> | 1 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution 2.5 Canada | <https://github.com/mdeff/fma> | 1 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution 3.0 International | <https://github.com/mdeff/fma> | 1 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution 3.0 United States | <https://github.com/mdeff/fma> | 2 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution-Share Alike 3.0 Germany | <https://github.com/mdeff/fma> | 1 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Attribution-ShareAlike 3.0 International | <https://github.com/mdeff/fma> | 4 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Creative Commons Attribution | <https://github.com/mdeff/fma> | 1 |
| Free Music Archive (FMA) small | 2017-05-09; fma_small SHA1 ade154f733639d52e35e32f5593efe5be76c6d70 | Public Domain | <https://github.com/mdeff/fma> | 1 |

## Selection and exclusions

- Selected rows have an existing audio file, a unique recording ID, a supported genre, and complete source/version/license/citation metadata.
- Accepted individual licenses are Public Domain, Attribution/CC Attribution, and Attribution-ShareAlike variants.
- NonCommercial (NC), NoDerivatives (ND), and unknown/unapproved licenses cause generation to fail; they are never silently included.
- Every selected source file was analyzed by `audio_engine.analyze_audio`; external precomputed features were not used as targets.
- The current FMA-derived Rock, Pop, and Hip-Hop cohorts have unverified instrumental status. Their numeric targets are provisional until regenerated from licensed, genre-representative instrumental or rendered-MIDI audio.
- Ballad, Classical, R&B, and General remain disabled because the manifest contains no compatible cohort for them.

## Derived quartiles

| Genre | Metric | p25 (lower) | Median (preferred) | p75 (upper) | Robust scale | Unit |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| rock | loudness | -23.003370042 | -20.5035669417 | -18.8771269219 | 4.12624312012 | LUFS |
| rock | bass | 51.196786418 | 59.8452998432 | 63.8465654492 | 12.6497790312 | percent |
| rock | treble | 1.98870747506 | 2.40076835404 | 3.25579523064 | 1.26708775558 | percent |
| rock | sharpness | 0.00424870578721 | 0.00539564365175 | 0.00638924650972 | 0.00214054072251 | normalized_score |
| rock | flatness | 0.000742955133319 | 0.000843035813887 | 0.00101326114964 | 0.000270306016319 | ratio |
| pop | loudness | -23.4607068022 | -16.5477504793 | -14.5250916717 | 8.9356151305 | LUFS |
| pop | bass | 46.4602874828 | 85.7336141912 | 87.75765844 | 41.2973709572 | percent |
| pop | treble | 0.305150041637 | 0.71834801603 | 0.974220690271 | 0.669070648633 | percent |
| pop | sharpness | 0.00163775874226 | 0.00253669419641 | 0.0043141605916 | 0.00267640184934 | normalized_score |
| pop | flatness | 5.90546660533e-05 | 0.00024916412076 | 0.000769887235947 | 0.000710832569894 | ratio |
| hip-hop | loudness | -19.8001298361 | -16.7244067751 | -15.4900611009 | 4.31006873526 | LUFS |
| hip-hop | bass | 46.7928047926 | 66.3308800481 | 78.3189335339 | 31.5261287413 | percent |
| hip-hop | treble | 2.06485873301 | 3.41992451206 | 5.04964122719 | 2.98478249418 | percent |
| hip-hop | sharpness | 0.00771717883122 | 0.00814030515872 | 0.00927346419604 | 0.00155628536483 | normalized_score |
| hip-hop | flatness | 0.000582155887969 | 0.000905416673049 | 0.00143670942634 | 0.000854553538375 | ratio |
