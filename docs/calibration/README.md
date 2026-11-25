# Microphone calibration

KaraOK measures the phone in five seconds of silence and fifteen seconds of pink noise. A saved calibration adjusts the level and frequency response used to measure loudness, bass, treble, sharpness, and flatness. The silent portion also helps Noise Guard recognize the phone's own microphone hiss.

## Set up the reference phone

1. Choose one karaoke machine and mark its calibration volume. Center its EQ, bass, and treble controls and turn echo off.
2. Place the phone one metre from the speaker at speaker height, with the microphone pointing toward the speaker. Use a quiet room.
3. Connect a laptop or second phone to the machine and load [karaok_pink_noise_30s.wav](karaok_pink_noise_30s.wav). You can also connect the recording phone to the machine and select **Play on this phone**.
4. Open **Settings → Microphone calibration**, start recording, and keep the first five seconds quiet. Play the WAV when prompted. Note the calibration ID that appears after upload.
5. From the backend directory on the server, run:

   ```bash
   python3 scripts/set_mic_calibration_reference.py --measurement-id ab12cd34 --note "Reference phone, machine and marked volume"
   ```

   If the service uses a custom upload directory, set `AUDIO_UPLOAD_DIR` in the script environment or pass `--log /path/to/uploads/calibration/measurements.jsonl`. Use `--out` to test with a different destination. The server reads the reference file on each calibration request.
6. Calibrate each phone, including the reference phone, using that same machine, room, playback volume, EQ, and phone position.

The offsets are relative to the phone and machine used to make the reference. Use the same machine and marked setup for each phone calibration. During assessments, keep the microphone location and orientation consistent. Run calibration again if the phone or microphone changes or the server operator replaces the reference.
