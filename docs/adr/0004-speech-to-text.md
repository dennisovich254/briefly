# ADR 0004: Deepgram streaming is the default speech-to-text, with the audio source as the speaker

- **Status:** Proposed (accepted when the owner merges the 1.6 pull request)
- **Date:** 2026-11-05
- **Decides:** architecture §18 A04 (cloud streaming speech-to-text by default on 4 GB; Claude for reasoning) and A12 (the speaker side from the audio source, not diarization)
- **Evidence:** spike S3, plan 1.6: `tests/audio/`, `tests/stt/`, `bench/stt_score.jac` on the owner's reading, `bench/results/stt-20261105T1739Z.json`

## Context

§9.1 needs two separate streams (the meeting application's output as "others", the microphone as "me"), a streaming transcript of each, and a vocabulary taken from the brief. §9.3 leaves the service to this spike: latency, accuracy on names and code terms, vocabulary support, retention terms and price.

**Claude takes no audio.** The Messages API's input blocks are text, image, document, search results and tool blocks, with no audio and no realtime voice input (API reference, read 2026-11-05). Transcription is a separate step, as §9.3 assumed.

**Capture (A12).** Each source is captured by its own `pw-record` process targeting that one PipeWire node, as 16 kHz mono PCM read live into a 30-second ring buffer, with nothing on disk. With a 440 Hz tone from a fake meeting app and an 880 Hz tone on a virtual microphone, each capture held only its own tone. That covers the meeting app's playback stream, not just a sink monitor. Capture starts in 0.2 s, needs no system package beyond PipeWire's own tools (no PortAudio), and is tested in CI inside a private PipeWire session.

**The comparison.** The owner read a fixed 154-second standup (`bench/stt/standup_script.txt`, both speakers' lines) into the laptop's microphone. Each engine was given the recording at real-time pace, with the 26 terms of `bench/stt/terms.txt` as vocabulary where it accepts one:

| Engine | Word error rate | Key terms right | End of speech to final text, p50 / p95 | Price | This run |
|---|---|---|---|---|---|
| Deepgram Nova-3 (cloud) | 12.5 % | 22 / 26 | 0.50 / 2.27 s | $0.0090/min with key terms | $0.023 |
| AssemblyAI Universal Streaming English (cloud) | 13.8 % | 22 / 26 | 0.70 / 1.54 s | $0.19/h with key terms, billed while the connection is open | $0.008 |
| Vosk small English (local) | 51.9 % | 2 / 26 | 0.95 / 1.13 s | free; 155 MB, twice real time on two cores | $0 |

Both cloud services missed "JD-038" and "WirePlumber". Deepgram also missed "Vosk" and wrote "post GreSQL". AssemblyAI wrote "Jacques" for Jac and "ADR 000. 3", a formatting split the scorer does not accept. Vosk takes no vocabulary list, and heard "PipeWire" as "vibe wire".

**Retention.** Deepgram excludes a request from its model-improvement programme with `mip_opt_out=true`, on any account, free included. AssemblyAI's free accounts cannot opt out of training; paid accounts can, and then get zero retention for streaming.

## Decision

1. **Deepgram Nova-3 streaming is the default speech-to-text (A04 confirmed).** Its accuracy ties AssemblyAI's on the terms that matter and leads on words, it has the lower median lag, and every request opts out of training (`mip_opt_out=true`), which matters because the "others" stream carries other people's speech. At $0.54 an hour, the $200 sign-up credit covers about 370 hours, or years of daily standups.
2. **AssemblyAI is the second option behind the same engine interface**, for when Deepgram is unreachable. On a free account it is offered only with a plain statement that the audio may be used for training. A switch is never silent (§9.3).
3. **The local Vosk model is not a live-assistance option on the 4 GB laptop.** At 2 of 26 terms it cannot recognize the questions Briefly answers. The local choice is typed input (§9.3), and a Whisper-class model remains the local default for 8 GB+ machines.
4. **The speaker is the audio source (A12 confirmed).** "others" is the meeting application's playback stream, "me" the default microphone, each a separate capture, with no diarization model.
5. **The vocabulary is the brief's terms**, sent per session as Deepgram `keyterm`s (500 tokens) or AssemblyAI `keyterms_prompt` (100 terms).

## Consequences

- At the 95th percentile, both services miss the illustrative 1.2 s share of §13's voice budget (2.27 s and 1.54 s). The whole pipeline is measured against p50 ≤ 3 s and p95 ≤ 6 s in phase 5 (5.5), where Deepgram's endpointing (300 ms here) and interim results can be tuned.
- The evidence is one 2.5-minute reading by one speaker into a laptop microphone. Meeting audio of other people, compressed by the meeting client, is re-scored in phase 5 with `bench/stt_score.jac`, on recordings made with every participant's consent.
- The §13 meeting-phase memory measurement moves to 5.2, where capture and speech-to-text run together during a real call.
- The cloud keys are development settings in `.env`. Installed apps keep them in the OS keyring (§14.3).
- `websockets` is a product dependency, and Vosk a dev dependency only.
