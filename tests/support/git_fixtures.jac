"""Throwaway Git repositories with a scripted history, for collector tests (plan 0.4).

Git runs with the user's global and system config ignored and a fixed identity, so a fixture is
the same on every machine. Commit dates start at 2026-01-05 09:00 UTC and advance one hour per
commit, so SHAs are reproducible. Callers own the directory: create fixtures inside a
`tempfile.TemporaryDirectory()` so they are removed afterwards.
"""
import os;
import subprocess;

glob START_EPOCH: int = 1767603600;  # 2026-01-05T09:00:00Z
glob DEV: tuple[str, str] = ("Fixture Dev", "dev@example.invalid");
glob OTHER: tuple[str, str] = ("Other Dev", "other@example.invalid");
glob PAIR: str = "Pair Dev <pair@example.invalid>";

obj GitFixture {
    has path: str,
        commits: int = 0;

    """The environment Git runs in: no inherited GIT_* variables, no global or system config."""
    def env -> dict[str, str] {
        clean = {
            k: v
            for (k, v) in os.environ.items()
            if not k.startswith("GIT_")
        };
        clean.update(
            {
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_TERMINAL_PROMPT": "0",
                "LC_ALL": "C"
            }
        );
        return clean;
    }

    """Run git in the repository; returns stdout without its trailing newline."""
    def git(
        args: list[str], check: bool = True, extra_env: dict[str, str] = {}
    ) -> str {
        env = self.env();
        env.update(extra_env);
        done = subprocess.run(
            ["git", "-C", self.path] + args,
            env=env,
            capture_output=True,
            text=True,
            timeout=60
        );
        if check and done.returncode != 0 {
            raise RuntimeError(f"git {' '.join(args)} failed: {done.stderr.strip()}");
        }
        return done.stdout.rstrip("\n");
    }

    def write(rel: str, text: str) -> None {
        target = os.path.join(self.path, rel);
        os.makedirs(os.path.dirname(target), exist_ok=True);
        with open(target, "w") as fh {
            fh.write(text);
        }
    }

    """Stage everything and commit it at the next fixture hour; returns the new SHA."""
    def commit(
        message: str, author: tuple[str, str] = DEV, trailers: list[str] = []
    ) -> str {
        stamp = f"@{START_EPOCH + self.commits * 3600} +0000";
        self.commits += 1;
        body = message + ("\n\n" + "\n".join(trailers) if trailers else "");
        self.git(["add", "-A"]);
        self.git(
            ["commit", "-q", "--no-verify", "--no-gpg-sign", "-m", body],
            extra_env={
                "GIT_AUTHOR_NAME": author[0],
                "GIT_AUTHOR_EMAIL": author[1],
                "GIT_AUTHOR_DATE": stamp,
                "GIT_COMMITTER_DATE": stamp
            }
        );
        return self.git(["rev-parse", "HEAD"]);
    }
}

"""An empty repository at <base>/<name> on branch main, with the fixture identity."""
def make_repo(base: str, name: str) -> GitFixture {
    repo = GitFixture(path=os.path.join(base, name));
    os.makedirs(repo.path);
    repo.git(["init", "-q", "-b", "main"]);
    repo.git(["config", "user.name", DEV[0]]);
    repo.git(["config", "user.email", DEV[1]]);
    repo.git(["config", "commit.gpgsign", "false"]);
    return repo;
}

"""The history collector tests start from (<base>/standard, plus <base>/standard-detached).

main:             Initial project · Add weekly report (Other Dev)
feature/notices:  Initial project · Add notice expiry (co-authored by Pair Dev)
                  · Rename notes to design (docs/notes.md -> docs/design.md) · Remove scratch file
HEAD is feature/notices with src/notices.py staged, README.md modified and todo.txt untracked.
A second worktree, standard-detached, has main checked out on a detached HEAD.
"""
def standard_history(base: str) -> GitFixture {
    repo = make_repo(base, "standard");
    repo.write("README.md", "# Notices service\n");
    repo.write("src/notices.py", "def notices():\n    return []\n");
    repo.write("docs/notes.md", "Design notes.\n");
    repo.write("scratch.txt", "temporary\n");
    repo.commit("Initial project");

    repo.git(["switch", "-q", "-c", "feature/notices"]);
    repo.write("src/notices.py", "def notices(expired=False):\n    return []\n");
    repo.commit("Add notice expiry", trailers=[f"Co-authored-by: {PAIR}"]);
    repo.git(["mv", "docs/notes.md", "docs/design.md"]);
    repo.commit("Rename notes to design");
    repo.git(["rm", "-q", "scratch.txt"]);
    repo.commit("Remove scratch file");

    repo.git(["switch", "-q", "main"]);
    repo.write("src/report.py", "def weekly():\n    return {}\n");
    repo.commit("Add weekly report", author=OTHER);

    repo.git(["switch", "-q", "feature/notices"]);
    repo.git(
        [
            "worktree",
            "add",
            "-q",
            "--detach",
            os.path.join(base, "standard-detached"),
            "main"
        ]
    );

    repo.write(
        "src/notices.py",
        "def notices(expired=False):\n    return [] if expired else []\n"
    );
    repo.git(["add", "src/notices.py"]);
    repo.write("README.md", "# Notices service\n\nWork in progress.\n");
    repo.write("todo.txt", "write tests\n");
    return repo;
}
