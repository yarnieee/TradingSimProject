"""Turns tb_sound's sound_<name>.txt files (one 0..255 sample a line) into .wav
files at the board's sample rate (100 MHz / 2048 = 48,828 Hz), to listen to.

    python3 sound_to_wav.py [folder with the .txt files]
"""
import glob
import os
import sys
import wave

RATE = 100_000_000 // 2048
folder = sys.argv[1] if len(sys.argv) > 1 else '.'
for txt in sorted(glob.glob(os.path.join(folder, 'sound_*.txt'))):
    samples = bytes(int(line) for line in open(txt) if line.strip())
    out = txt[:-4] + '.wav'
    with wave.open(out, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(1)                 # 8-bit WAV is unsigned, 128 = silence, as on the board
        w.setframerate(RATE)
        w.writeframes(samples)
    print('%s: %.2f s' % (out, len(samples) / RATE))
