"""How often the UI has been opened, kept in the graph (plan 1.3).

The first piece of graph state: the clean-install check (bench/install_check.sh) reads it after a
restart to prove the graph persists, and that the page's code ran and reached the server.
"""
import from core.clock { now }

node OpenHistory {
    has count: int = 0,
        first_opened: str = "";
}

obj AppOpens {
    has count: int,
        first_opened: str | None;
}

def history -> OpenHistory | None {
    found = [root-->][?:OpenHistory];
    return found[0] if found else None;
}

def view(h: OpenHistory | None) -> AppOpens {
    if h is None {
        return AppOpens(count=0, first_opened=None);
    }
    return AppOpens(count=h.count, first_opened=h.first_opened);
}

"""How many times the UI has been opened, and when it first was."""
def:pub app_opens -> AppOpens {
    return view(history());
}

"""Count one more open of the UI; returns the totals."""
def:pub record_open -> AppOpens {
    h = history();
    if h is None {
        h = OpenHistory(first_opened=now().isoformat());
        root ++> h;
    }
    h.count += 1;
    return view(h);
}
