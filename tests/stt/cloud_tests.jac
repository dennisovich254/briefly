"""The cloud speech-to-text engines against fake services (plan 1.6, spike S3). No key, no network.

Each fake is a local WebSocket server that records what the engine sent (headers, query, audio,
the closing message) and answers in the service's documented message shapes (core/stt/cloud.jac).
"""
import json;
import threading;
import urllib.parse;
import from websockets.http11 { Request }
import from websockets.sync.server { Server, ServerConnection, serve }
import core.stt.cloud as cloud;

glob VOCABULARY: list[str] = ["PipeWire", "byLLM", "JD-036", "phone link"],
     SECOND: bytes = b"\x00\x00" * 16000;

obj Seen {
    has path: str = "",
        auth: str = "",
        audio_bytes: int = 0,
        control: list[str] = [];

    def query -> dict[str, list[str]] {
        return urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query);
    }
}

obj Fake {
    has seen: Seen = Seen(),
        port: int = 0,
        _server: Server | None = None,
        _thread: threading.Thread | None = None;

    def run(handler: Callable[[ServerConnection], None]) {
        server = serve(handler, "127.0.0.1", 0);
        self._server = server;
        self.port = server.socket.getsockname()[1];
        self._thread = threading.Thread(target=server.serve_forever, daemon=True);
        self._thread.start();
    }

    def url -> str {
        return f"ws://127.0.0.1:{self.port}/stream";
    }

    def stop {
        if self._server is not None {
            self._server.shutdown();
        }
    }
}

def note_request(seen: Seen, ws: ServerConnection) {
    request = ws.request;
    if isinstance(request, Request) {
        seen.path = request.path;
        seen.auth = str(request.headers.get("Authorization", ""));
    }
}

"""Deepgram: an interim result after the first second of audio, a final one on CloseStream."""
def fake_deepgram(seen: Seen) -> Callable[[ServerConnection], None] {
    def handle(ws: ServerConnection) {
        note_request(seen, ws);
        sent_interim = False;
        for raw in ws {
            if isinstance(raw, bytes) {
                seen.audio_bytes = seen.audio_bytes + len(raw);
                if seen.audio_bytes >= 32000 and not sent_interim {
                    sent_interim = True;
                    ws.send(
                        json.dumps(
                            {
                                "type": "Results",
                                "is_final": False,
                                "start": 0.0,
                                "duration": 1.0,
                                "channel": {
                                    "alternatives": [{"transcript": "yesterday I"}]
                                }
                            }
                        )
                    );
                }
                continue;
            }
            seen.control.append(raw);
            if json.loads(raw).get("type") == "CloseStream" {
                ws.send(
                    json.dumps(
                        {
                            "type": "Results",
                            "is_final": True,
                            "start": 0.0,
                            "duration": 1.9,
                            "channel": {
                                "alternatives": [
                                    {
                                        "transcript": "Yesterday I merged the PipeWire fix."
                                    }
                                ]
                            }
                        }
                    )
                );
                ws.send(json.dumps({"type": "Metadata", "request_id": "fake"}));
                ws.close();
                return;
            }
        }
    }
    return handle;
}

"""AssemblyAI: Begin, an open turn, then on Terminate the unformatted and formatted end of turn."""
def fake_assemblyai(seen: Seen) -> Callable[[ServerConnection], None] {
    def handle(ws: ServerConnection) {
        note_request(seen, ws);
        ws.send(json.dumps({"type": "Begin", "id": "fake", "expires_at": 0}));
        sent_open = False;
        for raw in ws {
            if isinstance(raw, bytes) {
                seen.audio_bytes = seen.audio_bytes + len(raw);
                if seen.audio_bytes >= 32000 and not sent_open {
                    sent_open = True;
                    ws.send(
                        json.dumps(
                            {
                                "type": "Turn",
                                "turn_order": 0,
                                "end_of_turn": False,
                                "turn_is_formatted": False,
                                "transcript": "today i",
                                "words": [{"text": "today", "start": 100, "end": 400}]
                            }
                        )
                    );
                }
                continue;
            }
            seen.control.append(raw);
            if json.loads(raw).get("type") == "Terminate" {
                ws.send(
                    json.dumps(
                        {
                            "type": "Turn",
                            "turn_order": 0,
                            "end_of_turn": True,
                            "turn_is_formatted": False,
                            "transcript": "today i work on byllm",
                            "words": [{"text": "byllm", "start": 1500, "end": 1800}]
                        }
                    )
                );
                ws.send(
                    json.dumps(
                        {
                            "type": "Turn",
                            "turn_order": 0,
                            "end_of_turn": True,
                            "turn_is_formatted": True,
                            "transcript": "Today I work on byLLM.",
                            "words": [{"text": "byLLM.", "start": 1500, "end": 1800}]
                        }
                    )
                );
                ws.send(
                    json.dumps({"type": "Termination", "audio_duration_seconds": 2})
                );
                ws.close();
                return;
            }
        }
    }
    return handle;
}

def stream_two_seconds(engine: cloud.DeepgramEngine | cloud.AssemblyAIEngine) {
    engine.start(VOCABULARY);
    for _ in range(20) {
        engine.feed(SECOND[:3200]);
    }
    engine.finish();
}

test "the Deepgram query asks for Nova-3, raw 16 kHz PCM, no training, and one keyterm per term" {
    q = urllib.parse.parse_qs(cloud.deepgram_query(VOCABULARY));
    assert q["model"] == ["nova-3"]
        and q["encoding"] == ["linear16"]
        and q["sample_rate"] == ["16000"];
    assert q["mip_opt_out"] == ["true"] and q["interim_results"] == ["true"];
    assert q["keyterm"] == VOCABULARY , q["keyterm"];
}

test "the AssemblyAI query sends the vocabulary as JSON, within its limits" {
    long_term = "x" * 51;
    many = [f"term{i}" for i in range(120)];
    q = urllib.parse.parse_qs(cloud.assemblyai_query(["PipeWire", long_term] + many));
    terms = json.loads(q["keyterms_prompt"][0]);
    assert terms[0] == "PipeWire" and long_term not in terms , terms[:3];
    assert len(terms) == cloud.MAX_ASSEMBLYAI_TERMS;
    assert q["speech_model"] == ["universal-streaming-english"]
        and q["encoding"] == ["pcm_s16le"];
}

test "the Deepgram engine streams the audio, closes the stream, and keeps only final text as final" {
    fake = Fake();
    fake.run(fake_deepgram(fake.seen));
    try {
        engine = cloud.DeepgramEngine(tag="others", url=fake.url(), key="dg-test-key");
        stream_two_seconds(engine);
        assert fake.seen.auth == "Token dg-test-key" , fake.seen.auth;
        assert fake.seen.query()["keyterm"] == VOCABULARY;
        assert fake.seen.audio_bytes == 64000 , fake.seen.audio_bytes;
        assert [json.loads(c)["type"] for c in fake.seen.control] == ["CloseStream"];
        finals = engine.transcript.finals();
        assert [u.text for u in finals] == ["Yesterday I merged the PipeWire fix."];
        assert finals[0].tag == "others" and abs(finals[0].audio_end - 1.9) < 1e-6;
        partials = [
            u
            for u in engine.transcript.utterances
            if not u.final
        ];
        assert [u.text for u in partials] == ["yesterday I"];
        assert engine.transcript.error == "" , engine.transcript.error;
    } finally {
        fake.stop();
    }
}

test "the AssemblyAI engine sends the bare key, terminates, and takes a turn as final once formatted" {
    fake = Fake();
    fake.run(fake_assemblyai(fake.seen));
    try {
        engine = cloud.AssemblyAIEngine(
            tag="others", url=fake.url(), key="aai-test-key"
        );
        stream_two_seconds(engine);
        assert fake.seen.auth == "aai-test-key" , fake.seen.auth;
        assert json.loads(fake.seen.query()["keyterms_prompt"][0]) == VOCABULARY;
        assert fake.seen.audio_bytes == 64000;
        assert [json.loads(c)["type"] for c in fake.seen.control] == ["Terminate"];
        finals = engine.transcript.finals();
        assert [u.text for u in finals] == ["Today I work on byLLM."] , [
            u.text for u in engine.transcript.utterances
        ];
        assert abs(finals[0].audio_end - 1.8) < 1e-6;
    } finally {
        fake.stop();
    }
}

test "a service error is kept on the transcript" {
    fake = Fake();
    def refuse(ws: ServerConnection) {
        for raw in ws {
            if not isinstance(raw, bytes) {
                ws.send(json.dumps({"type": "Error", "description": "INVALID_AUTH"}));
                ws.close();
                return;
            }
        }
    }
    fake.run(refuse);
    try {
        engine = cloud.DeepgramEngine(tag="me", url=fake.url(), key="bad");
        stream_two_seconds(engine);
        assert engine.transcript.error == "INVALID_AUTH" , engine.transcript.error;
    } finally {
        fake.stop();
    }
}

test "an engine without a key refuses to start" {
    engine = cloud.AssemblyAIEngine(tag="me", url="ws://127.0.0.1:9/never", key="");
    import os;
    saved = os.environ.pop("ASSEMBLYAI_API_KEY", None);
    cwd = os.getcwd();
    import tempfile;
    with tempfile.TemporaryDirectory() as empty {
        os.chdir(empty);
        try {
            engine.start(VOCABULARY);
            assert False , "started without a key";
        } except RuntimeError as e {
            assert "ASSEMBLYAI_API_KEY" in str(e);
        } finally {
            os.chdir(cwd);
            if saved is not None {
                os.environ["ASSEMBLYAI_API_KEY"] = saved;
            }
        }
    }
}
