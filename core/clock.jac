"""The app's clock. Domain code calls clock.now(), never the system clock directly.

Reporting windows ("since the last standup", architecture §8.4) depend on the time, so tests
freeze and advance this clock. Control is refused unless BRIEFLY_CLOCK_CONTROL=1, which only
scripts/test.sh sets, so shipped code cannot move time.
"""
import os;
import from datetime { datetime, timedelta, timezone }

glob CONTROL_ENV: str = "BRIEFLY_CLOCK_CONTROL";
glob _frozen: datetime | None = None;

obj ClockControlRefused(RuntimeError) {}

def _require_control -> None {
    if os.environ.get(CONTROL_ENV) != "1" {
        raise ClockControlRefused(f"clock control needs {CONTROL_ENV}=1 (tests only)");
    }
}

"""The current time, timezone-aware, in UTC."""
def now -> datetime {
    if _frozen is not None {
        return _frozen;
    }
    return datetime.now(timezone.utc);
}

"""Pin now() to `at` (timezone-aware) until reset()."""
def freeze(at: datetime) -> None {
    _require_control();
    if at.tzinfo is None {
        raise ValueError("freeze needs a timezone-aware datetime");
    }
    _frozen = at.astimezone(timezone.utc);
}

"""Move a frozen clock forward by `delta`."""
def advance(delta: timedelta) -> None {
    _require_control();
    if _frozen is None {
        raise ClockControlRefused("advance needs a frozen clock; call freeze first");
    }
    _frozen = _frozen + delta;
}

"""Return now() to the system clock."""
def reset -> None {
    _require_control();
    _frozen = None;
}
