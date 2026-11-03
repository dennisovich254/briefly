import os;
import tempfile;

glob MATRIX: str = """# Capability matrix

| Jac capability | Where the app exercises it | What is checked | Known inputs | 0.39.0 | Findings |
|---|---|---|---|---|---|
| Graph persistence and walkers | Evidence model | Correctness | JI-042 | Not yet exercised | |
| Test runner (`jac test`) | Unit tests | Strict mode | JI-001 | Works | |
""";

glob FINDING: str = """# JD-001: Example behaviour

- **Version:** jaclang 0.39.0, Ubuntu 24.04, desktop
- **Found:** 2026-11-03, phase 1 / S0
- **Category / severity:** Defect / Major
- **Capability:** Graph persistence and walkers
- **Status:** open
- **Related:** JI-042
- **Cost:** 2 h, 10 lines
- **Canary:** tests/canaries/jd_001_example.jac

## Behaviour
""";

glob INDEX: str = """# Jac findings

| ID | Behaviour | Severity | Status |
|---|---|---|---|
| [JD-001](JD-001-example.md) | Example behaviour | Major | open |
""";

"""Check a throwaway repository holding `files`; the repository is removed afterwards."""
def check_files(files: dict[str, str]) -> list[str] {
    with tempfile.TemporaryDirectory(prefix="briefly-findings-") as base {
        for (rel, text) in files.items() {
            path = os.path.join(base, rel);
            os.makedirs(os.path.dirname(path), exist_ok=True);
            with open(path, "w") as fh {
                fh.write(text);
            }
        }
        return check_tree(base);
    }
}

"""Check a valid log (one open finding and its canary) with `changes` applied on top."""
def check_with(changes: dict[str, str]) -> list[str] {
    files: dict[str, str] = {
        "docs/jac-findings/capability-matrix.md": MATRIX,
        "docs/jac-findings/README.md": INDEX,
        "docs/jac-findings/JD-001-example.md": FINDING,
        "tests/canaries/jd_001_example.jac": ""
    };
    for (rel, text) in changes.items() {
        files[rel] = text;
    }
    return check_files(files);
}

def errors_for(finding_text: str) -> list[str] {
    return check_with({"docs/jac-findings/JD-001-example.md": finding_text});
}

def mentions(errors: list[str], needle: str) -> bool {
    return `any([needle in e for e in errors]);
}

test "a valid log has no errors" {
    assert check_with(({})) == [];
}

test "an empty log has no errors" {
    errors = check_files(
        {
            "docs/jac-findings/capability-matrix.md": MATRIX,
            "docs/jac-findings/README.md": "# Jac findings\n\nNo findings yet.\n",

        }
    );
    assert errors == [];
}

test "a missing findings directory is an error" {
    assert mentions(check_files(({"README.md": ""})), "docs/jac-findings");
}

test "each required field must be present" {
    for field in [
        "Version",
        "Found",
        "Category / severity",
        "Capability",
        "Status",
        "Related",
        "Cost",
        "Canary"
    ] {
        text = "\n".join(
            [
                l
                for l in FINDING.splitlines()
                if not l.startswith(f"- **{field}:**")
            ]
        );
        errors = errors_for(text);
        assert mentions(errors, f"missing field '{field}'") , f"{field}: {errors}";
    }
}

test "an empty field is an error" {
    assert mentions(
        errors_for(FINDING.replace("**Related:** JI-042", "**Related:**")),
        "missing field 'Related'"
    );
}

test "the found date must be YYYY-MM-DD" {
    assert mentions(errors_for(FINDING.replace("2026-11-03", "3 Nov 2026")), "Found");
}

test "category and severity must be from the lists" {
    assert mentions(
        errors_for(FINDING.replace("Defect / Major", "Bug / Major")), "category 'Bug'"
    );
    assert mentions(
        errors_for(FINDING.replace("Defect / Major", "Defect / Huge")),
        "severity 'Huge'"
    );
    for cat in [
        "Defect",
        "Missing capability",
        "Documentation gap or error",
        "Packaging/install",
        "Performance/resource",
        "Developer-experience friction"
    ] {
        for sev in ["Blocker", "Major", "Minor", "Cosmetic"] {
            assert errors_for(FINDING.replace("Defect / Major", f"{cat} / {sev}"))
                == [] , f"{cat} / {sev}";
        }
    }
}

test "status must be one of the allowed forms" {
    for status in [
        "open",
        "reported (https://github.com/jaseci-labs/jaseci/issues/1)",
        "fixed in 0.40.1",
        "won't fix",
        "not a Jac issue (withdrawn)"
    ] {
        assert errors_for(FINDING.replace("**Status:** open", f"**Status:** {status}"))
            == [] , status;
    }
    for status in ["fixed", "reported", "closed", "fixed in soon"] {
        assert mentions(
            errors_for(FINDING.replace("**Status:** open", f"**Status:** {status}")),
            "status"
        ) , status;
    }
}

test "the capability must be a row of the matrix" {
    assert mentions(
        errors_for(FINDING.replace("Graph persistence and walkers", "Teleportation")),
        "capability 'Teleportation'"
    );
}

test "an open or reported finding needs an existing canary or a reason" {
    missing = FINDING.replace(
        "tests/canaries/jd_001_example.jac", "tests/canaries/jd_001_gone.jac"
    );
    assert mentions(errors_for(missing), "canary");
    reported_missing = missing.replace(
        "**Status:** open", "**Status:** reported (https://example.org/1)"
    );
    assert mentions(errors_for(reported_missing), "canary");
    reason = FINDING.replace(
        "tests/canaries/jd_001_example.jac", "none (install prompt, checked by hand)"
    );
    assert errors_for(reason) == [];
    assert mentions(
        errors_for(FINDING.replace("tests/canaries/jd_001_example.jac", "none")),
        "canary"
    );
}

test "a closed finding does not need its canary any more" {
    fixed = FINDING.replace("**Status:** open", "**Status:** fixed in 0.40.0").replace(
        "jd_001_example.jac", "jd_001_removed.jac"
    );
    assert errors_for(fixed) == [];
}

test "the title ID must match the file name" {
    assert mentions(errors_for(FINDING.replace("# JD-001:", "# JD-002:")), "title");
    bad_name = check_with(({"docs/jac-findings/JD-1-example.md": FINDING}));
    assert mentions(bad_name, "JD-1-example.md");
}

test "every finding must be in the index, and every index link must exist" {
    unlisted = check_with(({"docs/jac-findings/README.md": "# Jac findings\n"}));
    assert mentions(unlisted, "JD-001 is not listed");
    dangling = check_with(
        (
            {
                "docs/jac-findings/README.md": INDEX
                    + "| [JD-002](JD-002-nothing.md) | x | Minor | open |\n"
            }
        )
    );
    assert mentions(dangling, "JD-002-nothing.md");
}

test "matrix verdicts must be from the list" {
    for verdict in [
        "Works",
        "Works with workaround",
        "Fails",
        "Missing",
        "Not documented",
        "Not yet exercised"
    ] {
        assert check_with(
            (
                {
                    "docs/jac-findings/capability-matrix.md": MATRIX.replace(
                        "| Works |", f"| {verdict} |"
                    )
                }
            )
        )
            == [] , verdict;
    }
    bad = check_with(
        (
            {
                "docs/jac-findings/capability-matrix.md": MATRIX.replace(
                    "| Works |", "| Kinda |"
                )
            }
        )
    );
    assert mentions(bad, "verdict 'Kinda'");
}

test "the matrix needs at least one version column" {
    no_version = MATRIX.replace("| 0.39.0 |", "| Verdict |");
    assert mentions(
        check_with(({"docs/jac-findings/capability-matrix.md": no_version})),
        "version column"
    );
}
