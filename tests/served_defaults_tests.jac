"""No served function declares a default (JD-036).

An omitted argument of a `def:pub` or `def:protect` function arrives as the text of its default
("False", "None", "3"), so a default silently changes what the function does. Until the JD-036
canary shows a fix, every argument of a served function is required.
"""
import os;
import re;

glob SERVED: re.Pattern[str] = re.compile(
         r"def:(?:pub|protect)\s+(\w+)\s*\(([^)]*)\)", re.DOTALL
     ),
     ROOTS: list[str] = ["core", "ui", "hosts", "main.jac"];

def jac_files -> list[str] {
    found: list[str] = [];
    for top in ROOTS {
        if top.endswith(".jac") {
            found.append(top);
            continue;
        }
        for (folder, _, names) in os.walk(top) {
            found.extend(
                [
                    os.path.join(folder, n)
                    for n in names
                    if n.endswith(".jac")
                ]
            );
        }
    }
    return found;
}

test "no def:pub or def:protect function declares a default argument" {
    offenders: list[str] = [];
    for path in jac_files() {
        with open(path) as fh {
            source = fh.read();
        }
        for found in SERVED.finditer(source) {
            if "=" in found.group(2) {
                offenders.append(f"{path}: {found.group(1)}");
            }
        }
    }
    assert not offenders , f"served functions with defaults (JD-036): {offenders}";
}
