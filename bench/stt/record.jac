"""Record the owner reading the fixed standup (plan 1.6, spike S3). Run by the owner.

    jac run bench/stt/record.jac            # writes bench/private/standup.wav (git-ignored)

Shows the script, counts down, and records the default microphone (16 kHz mono) until Enter is
pressed. Read every line, both speakers', at a normal pace. The file stays on this laptop: only
the owner's own consented voice, used to score the speech-to-text engines (bench/stt_score.jac).
"""
import math;
import os;
import struct;
import sys;
import time;
import wave;
import core.audio.capture as capture;
import bench.stt.score as score;

glob OUT: str = os.path.join("bench", "private", "standup.wav");

def level(pcm: bytes) -> tuple[float, float] {
    count = len(pcm) // 2;
    if count == 0 {
        return (0.0, 0.0);
    }
    samples = struct.unpack(f"<{count}h", pcm[:count * 2]);
    peak = max([abs(s) for s in samples]) / 32768;
    rms = math.sqrt(sum([s * s for s in samples]) / count) / 32768;
    return (peak, rms);
}

def main -> int {
    mic = capture.default_microphone();
    if mic is None {
        print("No default microphone: check Settings > Sound > Input.");
        return 2;
    }
    lines = score.load_script();
    print(f"Microphone: {mic.name}\n");
    print("Read every line aloud, both speakers', pausing briefly between lines:\n");
    for (i, line) in enumerate(lines, 1) {
        print(f"  {i:2}. [{line.tag}] {line.text}");
    }
    input("\nPress Enter, wait for 'Recording', then start reading… ");
    for n in [3, 2, 1] {
        print(f"  {n}…");
        time.sleep(1);
    }
    audio = bytearray();
    def keep(_tag: str, chunk: bytes) {
        audio.extend(chunk);
    }
    recorder = capture.Capture(source=mic, tag="me");
    recorder.listeners.append(keep);
    recorder.start();
    print("Recording. Press Enter when you have read the last line.");
    input();
    recorder.stop();
    os.makedirs(os.path.dirname(OUT), exist_ok=True);
    with wave.open(OUT, "wb") as out {
        out.setnchannels(1);
        out.setsampwidth(2);
        out.setframerate(capture.SAMPLE_RATE);
        out.writeframes(bytes(audio));
    }
    seconds = len(audio) / capture.BYTES_PER_SECOND;
    (peak, rms) = level(bytes(audio));
    print(f"Saved {OUT}: {seconds:.0f} s, peak {peak:.2f}, average level {rms:.3f}.");
    if rms < 0.005 {
        print(
            "That is nearly silent: check the input device and its volume, then record again."
        );
        return 1;
    }
    if peak > 0.99 {
        print("The recording clips: lower the input volume a little and record again.");
        return 1;
    }
    return 0;
}

with entry {
    sys.exit(main());
}
