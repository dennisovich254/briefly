import os;
import from datetime { datetime, timedelta, timezone }
import from core.clock { ClockControlRefused, advance, freeze, now, reset }

glob T0: datetime = datetime(2026, 3, 2, 9, 30, tzinfo=timezone.utc);

test "now is timezone-aware UTC and close to the system clock" {
    reset();
    current = now();
    assert current.tzinfo == timezone.utc;
    assert abs((datetime.now(timezone.utc) - current).total_seconds()) < 5;
}

test "freeze pins now until reset" {
    try {
        freeze(T0);
        assert now() == T0;
        assert now() == T0;
    } finally {
        reset();
    }
    assert now() != T0;
}

test "advance moves a frozen clock" {
    try {
        freeze(T0);
        advance(timedelta(hours=25));
        assert now() == T0 + timedelta(hours=25);
    } finally {
        reset();
    }
}

test "freeze refuses a naive datetime" {
    with testraises(ValueError) {
        freeze(datetime(2026, 3, 2, 9, 30));
    }
}

test "advance refuses a clock that is not frozen" {
    reset();
    with testraises(ClockControlRefused) {
        advance(timedelta(minutes=1));
    }
}

test "control is refused unless BRIEFLY_CLOCK_CONTROL=1" {
    saved = os.environ.pop("BRIEFLY_CLOCK_CONTROL", None);
    try {
        with testraises(ClockControlRefused) {
            freeze(T0);
        }
        with testraises(ClockControlRefused) {
            reset();
        }
    } finally {
        if saved is not None {
            os.environ["BRIEFLY_CLOCK_CONTROL"] = saved;
        }
    }
    assert now() != T0;
}
