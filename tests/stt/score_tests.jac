"""The speech-to-text scorer (bench/stt/score.jac; plan 1.6, spike S3)."""
import bench.stt.score as score;

test "normalizing reads number words as digits and drops punctuation, hyphens and leading zeros" {
    assert score.normalize("JD-036, merged.") == ["jd", "36", "merged"];
    assert score.normalize("JD thirty six") == ["jd", "36"];
    assert score.normalize("issue ten thousand six hundred and two")
        == ["issue", "10602"];
    assert score.normalize("issue 10,602") == ["issue", "10602"];
    assert score.normalize("ADR zero zero zero three") == ["adr", "0", "0", "0", "3"];
    assert score.normalize("three hundred and seventy megabytes")
        == ["370", "megabytes"];
    assert score.normalize("one point six") == ["1", "point", "6"];
    assert score.normalize("version 1.2 and Wi-Fi")
        == ["version", "1.2", "and", "wi", "fi"];
}

test "word error rate counts substitutions, deletions and insertions over the reference" {
    assert score.word_error_rate("I merged the phone link", "I merged the phone link")
        == 0.0;
    assert score.word_error_rate("I merged the phone link", "I merged a phone link")
        == 0.2;
    assert score.word_error_rate("I merged the phone link", "I merged phone link")
        == 0.2;
    assert score.word_error_rate(
        "I merged the phone link", "so I merged the phone link"
    )
        == 0.2;
    assert score.word_error_rate("JD thirty six", "JD-36") == 0.0;
}

test "a term counts when any of its spellings appears" {
    terms = score.load_terms();
    names = [t.name for t in terms];
    assert "PipeWire" in names and "JD-036" in names;
    found = score.terms_found(terms, "We used pipe wire and JD 36, then Deep gram.");
    assert "PipeWire" in found and "JD-036" in found and "Deepgram" in found , found;
    assert "JD-035" not in found and "WirePlumber" not in found;
    assert "Vosk" not in score.terms_found(terms, "the vibe wire model");
}

test "the script has both speakers and every term appears in it" {
    lines = score.load_script();
    tags = {l.tag for l in lines};
    assert tags == {"others", "me"} , tags;
    terms = score.load_terms();
    missing = [
        t.name
        for t in terms
        if t.name not in score.terms_found(terms, score.reference_text(lines))
    ];
    assert not missing , f"terms the script never says: {missing}";
    assert score.word_error_rate(
        score.reference_text(lines), score.reference_text(lines)
    )
        == 0.0;
}
