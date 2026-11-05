"""Scoring a transcript against the fixed standup (plan 1.6, spike S3; architecture §9.3).

Two numbers per engine: the word error rate over the whole reading, and how many of the
question-critical terms (bench/stt/terms.txt) came out right. Both compare normalized text: lower
case, no punctuation, hyphens and slashes as spaces, number words read as digits ("ten thousand six
hundred and two" = "10602", "thirty six" = "36"; a run of single digits such as "zero zero zero
three" stays digit by digit), and leading zeros dropped ("036" = "36").
"""
import os;
import re;

glob HERE: str = os.path.dirname(os.path.abspath(__file__)),
     UNITS: dict[str, int] = {
         "zero": 0,
         "oh": 0,
         "one": 1,
         "two": 2,
         "three": 3,
         "four": 4,
         "five": 5,
         "six": 6,
         "seven": 7,
         "eight": 8,
         "nine": 9,
         "ten": 10,
         "eleven": 11,
         "twelve": 12,
         "thirteen": 13,
         "fourteen": 14,
         "fifteen": 15,
         "sixteen": 16,
         "seventeen": 17,
         "eighteen": 18,
         "nineteen": 19
     },
     TENS: dict[str, int] = {
         "twenty": 20,
         "thirty": 30,
         "forty": 40,
         "fifty": 50,
         "sixty": 60,
         "seventy": 70,
         "eighty": 80,
         "ninety": 90
     },
     SCALES: dict[str, int] = {"hundred": 100, "thousand": 1000};

def is_number_word(word: str) -> bool {
    return word in UNITS or word in TENS or word in SCALES;
}

"""Read one run of number words; single digits in a row stay separate digits."""
def read_number_run(words: list[str]) -> list[str] {
    if all([w in UNITS and UNITS[w] < 10 for w in words]) {
        return [str(UNITS[w]) for w in words];
    }
    total = 0;
    current = 0;
    for w in words {
        if w in UNITS {
            current = current + UNITS[w];
        } elif w in TENS {
            current = current + TENS[w];
        } elif w == "hundred" {
            current = max(current, 1) * 100;
        } elif w == "thousand" {
            total = total + max(current, 1) * 1000;
            current = 0;
        }
    }
    return [str(total + current)];
}

"""Normalized tokens of a text (see the module docstring)."""
def normalize(text: str) -> list[str] {
    lowered = text.lower();
    lowered = re.sub(r"(?<=\d),(?=\d{3})", "", lowered);
    lowered = re.sub(r"[-/_]", " ", lowered);
    lowered = re.sub(r"[^a-z0-9.' ]", " ", lowered);
    lowered = re.sub(r"(?<!\d)\.|\.(?!\d)", " ", lowered);
    lowered = lowered.replace("'", "");
    raw = [
        w
        for w in lowered.split()
        if w
    ];
    out: list[str] = [];
    i = 0;
    while i < len(raw) {
        if is_number_word(raw[i]) {
            j = i;
            run: list[str] = [];
            while j < len(raw)
                and (
                    is_number_word(raw[j])
                    or (
                        raw[j] == "and"
                        and run
                        and run[-1] in SCALES
                        and j + 1 < len(raw)
                        and is_number_word(raw[j + 1])
                    )
                ) {
                if raw[j] != "and" {
                    run.append(raw[j]);
                }
                j = j + 1;
            }
            out.extend(read_number_run(run));
            i = j;
        } else {
            out.append(raw[i]);
            i = i + 1;
        }
    }
    return [w.lstrip("0") or "0" if w.isdigit() else w for w in out];
}

"""Word error rate: word edits (substitutions, deletions, insertions) over the reference's words."""
def word_error_rate(reference: str, hypothesis: str) -> float {
    ref = normalize(reference);
    hyp = normalize(hypothesis);
    if not ref {
        return 0.0 if not hyp else 1.0;
    }
    previous = list(range(len(hyp) + 1));
    for (i, r) in enumerate(ref, 1) {
        row = [i] + [0] * len(hyp);
        for (j, h) in enumerate(hyp, 1) {
            row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (r != h));
        }
        previous = row;
    }
    return previous[len(hyp)] / len(ref);
}

obj Term {
    has name: str,
        spellings: list[list[str]];
}

def contains(tokens: list[str], phrase: list[str]) -> bool {
    n = len(phrase);
    return n > 0
        and any([tokens[i:i + n] == phrase for i in range(len(tokens) - n + 1)]);
}

"""The terms file: a term, then ` | ` and other accepted spellings; `#` starts a comment."""
def load_terms(path: str = "") -> list[Term] {
    found: list[Term] = [];
    with open(path or os.path.join(HERE, "terms.txt")) as fh {
        for line in fh {
            text = line.strip();
            if not text or text.startswith("#") {
                continue;
            }
            forms = [f.strip() for f in text.split("|")];
            found.append(Term(name=forms[0], spellings=[normalize(f) for f in forms]));
        }
    }
    return found;
}

"""The vocabulary fed to the services: each term as written."""
def vocabulary(terms: list[Term]) -> list[str] {
    return [t.name for t in terms];
}

"""Which terms the transcript got right (any accepted spelling, anywhere)."""
def terms_found(terms: list[Term], hypothesis: str) -> list[str] {
    tokens = normalize(hypothesis);
    return [
        t.name
        for t in terms
        if any([contains(tokens, s) for s in t.spellings])
    ];
}

obj ScriptLine {
    has tag: str,
        text: str;
}

"""The script's lines: `others:` or `me:`, then the words; `#` starts a comment."""
def load_script(path: str = "") -> list[ScriptLine] {
    lines: list[ScriptLine] = [];
    with open(path or os.path.join(HERE, "standup_script.txt")) as fh {
        for line in fh {
            text = line.strip();
            if not text or text.startswith("#") or ":" not in text {
                continue;
            }
            (tag, words) = text.split(":", 1);
            lines.append(ScriptLine(tag=tag.strip(), text=words.strip()));
        }
    }
    return lines;
}

def reference_text(lines: list[ScriptLine]) -> str {
    return " ".join([l.text for l in lines]);
}
