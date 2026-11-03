"""Checks the Jac findings log (docs/jac-findings/): entry fields, index, capability matrix.

Usage: jac run scripts/check_findings.jac [repo root]   (exits 1 on any problem)
The rules are those of architecture §21.3-§21.5 and IMPLEMENTATION_PLAN 0.2.
"""
import os;
import re;
import sys;

glob FINDINGS_DIR: str = "docs/jac-findings";
glob FINDING_FILE: str = r"^JD-(\d{3})-[a-z0-9-]+\.md$";
glob REQUIRED_FIELDS: list[str] = [
         "Version",
         "Found",
         "Category / severity",
         "Capability",
         "Status",
         "Related",
         "Cost",
         "Canary"
     ];
glob CATEGORIES: list[str] = [
         "Defect",
         "Missing capability",
         "Documentation gap or error",
         "Packaging/install",
         "Performance/resource",
         "Developer-experience friction"
     ];
glob SEVERITIES: list[str] = ["Blocker", "Major", "Minor", "Cosmetic"];
glob VERDICTS: list[str] = [
         "Works",
         "Works with workaround",
         "Fails",
         "Missing",
         "Not documented",
         "Not yet exercised"
     ];
glob OPEN_STATUSES: list[str] = [r"^open$", r"^reported \(.+\)$"];
glob CLOSED_STATUSES: list[str] = [
         r"^fixed in \d+\.\d+\.\d+$",
         r"^won't fix$",
         r"^not a Jac issue \(withdrawn\)$"
     ];

def read_text(path: str) -> str {
    with open(path, encoding="utf-8") as fh {
        return fh.read();
    }
}

def matches_any(patterns: list[str], text: str) -> bool {
    return `any([re.match(p, text) is not None for p in patterns]);
}

"""Cells of a Markdown table row, without the outer pipes."""
def cells(line: str) -> list[str] {
    return [c.strip() for c in line.strip().strip("|").split("|")];
}

"""Capability names (first column) and verdict problems from capability-matrix.md."""
def parse_matrix(text: str) -> tuple[list[str], list[str]] {
    capabilities: list[str] = [];
    errors: list[str] = [];
    header: list[str] = [];
    version_cols: list[int] = [];
    for line in text.splitlines() {
        if not line.startswith("|") {
            continue;
        }
        row = cells(line);
        if not header {
            header = row;
            version_cols = [
                i
                for (i, h) in enumerate(row)
                if re.fullmatch(r"\d+\.\d+\.\d+", h)
            ];
            if not version_cols {
                errors.append(
                    "capability-matrix.md: the table has no version column (a header like '0.39.0')"
                );
            }
            continue;
        }
        if all([set(c) <= set("-: ") for c in row]) {
            continue;
        }
        capabilities.append(row[0]);
        for i in version_cols {
            verdict = row[i] if i < len(row) else "";
            if verdict not in VERDICTS {
                errors.append(
                    f"capability-matrix.md: '{row[0]}' has verdict '{verdict}' for {header[
                        i
                    ]}; use one of {', '.join(VERDICTS)}"
                );
            }
        }
    }
    return (capabilities, errors);
}

"""The `- **Name:** value` header fields of a finding."""
def parse_fields(text: str) -> dict[str, str] {
    fields: dict[str, str] = {};
    for line in text.splitlines() {
        m = re.match(r"^- \*\*(.+?):\*\*\s*(.*)$", line);
        if m {
            fields[m.group(1)] = m.group(2).strip();
        }
    }
    return fields;
}

def check_finding(
    name: str, text: str, capabilities: list[str], repo_root: str
) -> list[str] {
    m = re.match(FINDING_FILE, name);
    if m is None {
        return [f"{name}: file name must be JD-NNN-<slug>.md (lower-case slug)"];
    }
    errors: list[str] = [];
    fid = f"JD-{m.group(1)}";
    lines = text.splitlines();
    if not lines or not lines[0].startswith(f"# {fid}: ") {
        errors.append(f"{name}: title must start with '# {fid}: '");
    }
    fields = parse_fields(text);
    for field in REQUIRED_FIELDS {
        if not fields.get(field, "") {
            errors.append(f"{name}: missing field '{field}'");
        }
    }
    found = fields.get("Found", "");
    if found and re.match(r"^\d{4}-\d{2}-\d{2}\b", found) is None {
        errors.append(
            f"{name}: Found must start with a YYYY-MM-DD date, got '{found}'"
        );
    }
    cat_sev = fields.get("Category / severity", "");
    if cat_sev {
        parts = [p.strip() for p in cat_sev.split(" / ")];
        if len(parts) != 2 {
            errors.append(
                f"{name}: Category / severity must be '<category> / <severity>', got '{cat_sev}'"
            );
        } else {
            if parts[0] not in CATEGORIES {
                errors.append(
                    f"{name}: category '{parts[0]}' is not one of {', '.join(
                        CATEGORIES
                    )}"
                );
            }
            if parts[1] not in SEVERITIES {
                errors.append(
                    f"{name}: severity '{parts[1]}' is not one of {', '.join(
                        SEVERITIES
                    )}"
                );
            }
        }
    }
    status = fields.get("Status", "");
    is_open = matches_any(OPEN_STATUSES, status);
    if status and not is_open and not matches_any(CLOSED_STATUSES, status) {
        errors.append(
            f"{name}: status '{status}' must be: open | reported (<link>) | fixed in x.y.z | won't fix | not a Jac issue (withdrawn)"
        );
    }
    capability = fields.get("Capability", "");
    if capability and capability not in capabilities {
        errors.append(
            f"{name}: capability '{capability}' is not a row of capability-matrix.md"
        );
    }
    canary = fields.get("Canary", "");
    if canary and is_open {
        has_reason = canary.startswith("none (")
            and canary.endswith(")")
            and len(canary) > len("none ()");
        if not has_reason and not os.path.isfile(os.path.join(repo_root, canary)) {
            errors.append(
                f"{name}: canary '{canary}' does not exist; name the canary file or write 'none (<reason>)'"
            );
        }
    }
    return errors;
}

def check_tree(repo_root: str) -> list[str] {
    base = os.path.join(repo_root, FINDINGS_DIR);
    if not os.path.isdir(base) {
        return [f"{FINDINGS_DIR}/ does not exist"];
    }
    errors: list[str] = [];
    capabilities: list[str] = [];
    matrix_path = os.path.join(base, "capability-matrix.md");
    if os.path.isfile(matrix_path) {
        (capabilities, matrix_errors) = parse_matrix(read_text(matrix_path));
        errors.extend(matrix_errors);
    } else {
        errors.append(f"{FINDINGS_DIR}/capability-matrix.md is missing");
    }
    index_path = os.path.join(base, "README.md");
    index = read_text(index_path) if os.path.isfile(index_path) else "";
    if not index {
        errors.append(f"{FINDINGS_DIR}/README.md (the index) is missing or empty");
    }
    names = sorted(
        [
            n
            for n in os.listdir(base)
            if n.startswith("JD-") and n.endswith(".md")
        ]
    );
    for name in names {
        errors.extend(
            check_finding(
                name, read_text(os.path.join(base, name)), capabilities, repo_root
            )
        );
        m = re.match(FINDING_FILE, name);
        if m is not None and f"]({name})" not in index {
            errors.append(f"{name}: JD-{m.group(1)} is not listed in README.md");
        }
    }
    for link in re.findall(r"\]\((JD-[^)]+\.md)\)", index) {
        if not os.path.isfile(os.path.join(base, link)) {
            errors.append(f"README.md links to {link}, which does not exist");
        }
    }
    return errors;
}

with entry:__main__ {
    repo = sys.argv[1] if len(sys.argv) > 1 else os.getcwd();
    problems = check_tree(repo);
    for p in problems {
        print(p);
    }
    if problems {
        print(f"{len(problems)} problem(s) in the findings log.");
        sys.exit(1);
    }
    print("Findings log OK.");
}
