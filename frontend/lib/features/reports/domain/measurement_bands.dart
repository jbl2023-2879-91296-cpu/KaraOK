/// Advisory labels for the background-noise estimate.
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
    'A usable noise check helps KaraOK measure background noise before the song and reduce it where possible.';

const noiseCaution =
    'More negative numbers mean quieter sound. If KaraOK estimates noise from the quieter parts of the recording, music in those parts can raise the estimate.';

const noiseUncertain =
    'Not enough quiet moments to judge background noise. To check, record a few seconds of silence before the song starts.';
