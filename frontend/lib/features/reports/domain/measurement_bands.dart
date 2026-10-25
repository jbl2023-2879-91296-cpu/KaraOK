/// Advisory bands only. Neither estimate changes the saved quality score.
String noiseBand(num value) => value <= -60
    ? 'Quiet background'
    : value <= -45
    ? 'Some background noise'
    : 'Noisy background — you may hear hiss, hum or room noise';

String distortionBand(num value) => value < 20
    ? 'Low risk — no obvious crackling or clipping'
    : value < 50
    ? 'Some risk — listen for crackle at loud parts'
    : 'High risk — the sound may be clipping. Try lowering the volume or microphone gain.';

const noiseImplication =
    "This is about the room and the recording, not your score. Background noise doesn't change the quality score.";

const noiseCaution =
    'More negative numbers mean quieter sound. Music in the quiet parts can raise this estimate, so listen for noise before changing your setup.';
