import os;
import tempfile;
import from tests.support.git_fixtures { GitFixture, make_repo, standard_history }

test "make_repo creates an empty repository on main" {
    with tempfile.TemporaryDirectory() as base {
        repo = make_repo(base, "empty");
        assert os.path.isdir(os.path.join(repo.path, ".git"));
        assert repo.git(["symbolic-ref", "--short", "HEAD"]) == "main";
    }
}

test "commits use the fixed identity and dates, whatever the user's git config" {
    with tempfile.TemporaryDirectory() as base {
        repo = make_repo(base, "identity");
        repo.write("a.txt", "a\n");
        sha = repo.commit("first");
        assert len(sha) == 40;
        assert repo.git(["log", "-1", "--format=%an <%ae>"])
            == "Fixture Dev <dev@example.invalid>";
        assert repo.git(["log", "-1", "--format=%aI"]) == "2026-01-05T09:00:00Z";
        again = make_repo(base, "identity-again");
        again.write("a.txt", "a\n");
        assert again.commit("first") == sha , "same content, identity and date must give the same SHA";
    }
}

test "commit dates advance one hour per commit" {
    with tempfile.TemporaryDirectory() as base {
        repo = make_repo(base, "dates");
        repo.write("a.txt", "1\n");
        repo.commit("one");
        repo.write("a.txt", "2\n");
        repo.commit("two");
        assert repo.git(["log", "-1", "--format=%aI"]) == "2026-01-05T10:00:00Z";
    }
}

test "the repository ignores global and system git config" {
    with tempfile.TemporaryDirectory() as base {
        repo = make_repo(base, "isolated");
        assert repo.git(
            ["config", "--show-origin", "--get-all", "user.name"]
        ).startswith(
            "file:.git/config"
        );
        assert repo.git(["config", "--get", "core.hooksPath"], check=False) == "";
    }
}

test "standard_history has the scripted branches, commits and authors" {
    with tempfile.TemporaryDirectory() as base {
        repo = standard_history(base);
        branches = repo.git(["branch", "--format=%(refname:short)"]).splitlines();
        assert "main" in branches and "feature/notices" in branches , branches;
        authors = set(repo.git(["log", "--all", "--format=%an"]).splitlines());
        assert authors == {"Fixture Dev", "Other Dev"} , authors;
        trailers = repo.git(
            ["log", "--all", "--format=%(trailers:key=Co-authored-by,valueonly)"]
        );
        assert "Pair Dev <pair@example.invalid>" in trailers;
    }
}

test "standard_history records a rename and a deletion" {
    with tempfile.TemporaryDirectory() as base {
        repo = standard_history(base);
        changes = repo.git(["log", "--all", "-M", "--name-status", "--format="]);
        assert "R100\tdocs/notes.md\tdocs/design.md" in changes , changes;
        assert "D\tscratch.txt" in changes , changes;
    }
}

test "standard_history leaves staged, unstaged and untracked changes" {
    with tempfile.TemporaryDirectory() as base {
        repo = standard_history(base);
        status = repo.git(["status", "--porcelain=v1"]).splitlines();
        assert "M  src/notices.py" in status , status;
        assert " M README.md" in status , status;
        assert "?? todo.txt" in status , status;
    }
}

test "standard_history has a second worktree on a detached HEAD" {
    with tempfile.TemporaryDirectory() as base {
        repo = standard_history(base);
        worktrees = repo.git(["worktree", "list", "--porcelain"]);
        assert worktrees.count("worktree ") == 2 , worktrees;
        assert "detached" in worktrees , worktrees;
        detached = GitFixture(path=os.path.join(base, "standard-detached"));
        assert detached.git(["rev-parse", "--abbrev-ref", "HEAD"]) == "HEAD";
    }
}

test "fixture repositories live under the caller's directory" {
    with tempfile.TemporaryDirectory() as base {
        repo = standard_history(base);
        assert os.path.commonpath([base, repo.path]) == base;
    }
}
