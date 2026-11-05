"""The app's clock. Domain code calls clock.now(), never the system clock directly.

Reporting windows ("since the last standup", architecture §8.4) depend on the time, so tests
freeze and advance this clock. Control is refused unless BRIEFLY_CLOCK_CONTROL=1, which only
scripts/test.sh sets, so shipped code cannot move time: without it, now() ignores a frozen time.

The frozen time is kept in the environment (BRIEFLY_CLOCK_FROZEN_AT, ISO 8601), not in a module
variable: JacTestClient serves the app from its own copy of every module, so a module variable set
by a test never reaches the served app, while the environment is shared by every copy (JD-025).
"""
import os;
import from datetime { datetime, timedelta, timezone }

glob CONTROL_ENV: str = "BRIEFLY_CLOCK_CONTROL",
     FROZEN_ENV: str = "BRIEFLY_CLOCK_FROZEN_AT";

obj ClockControlRefused(RuntimeError) {}

def _controlled -> bool {
    return os.environ.get(CONTROL_ENV) == "1";
}

def _require_control {
    if not _controlled() {
        raise ClockControlRefused(f"clock control needs {CONTROL_ENV}=1 (tests only)");
    }
}

def _frozen -> datetime | None {
    value = os.environ.get(FROZEN_ENV, "");
    if not value or not _controlled() {
        return None;
    }
    return datetime.fromisoformat(value);
}

"""The current time, timezone-aware, in UTC."""
def now -> datetime {
    return _frozen() or datetime.now(timezone.utc);
}

"""Pin now() to `at` (timezone-aware) until reset()."""
def freeze(at: datetime) {
    _require_control();
    if at.tzinfo is None {
        raise ValueError("freeze needs a timezone-aware datetime");
    }
    os.environ[FROZEN_ENV] = at.astimezone(timezone.utc).isoformat();
}

"""Move a frozen clock forward by `delta`."""
def advance(delta: timedelta) {
    _require_control();
    frozen = _frozen();
    if frozen is None {
        raise ClockControlRefused("advance needs a frozen clock; call freeze first");
    }
    os.environ[FROZEN_ENV] = (frozen + delta).isoformat();
}

"""Return now() to the system clock."""
def reset {
    _require_control();
    os.environ.pop(FROZEN_ENV, None);
}
