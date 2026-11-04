"""Ask an X11 window to close, the way a title-bar close button does (plan 1.2).

Sends `_NET_CLOSE_WINDOW` to the root window for the client window titled $WINDOW_TITLE, so the
window manager delivers a normal close request. The desktop app's window is an X11 window under
XWayland (its launcher sets GDK_BACKEND=x11). Prints the window id; exits 1 if no window matched.
    WINDOW_TITLE=Briefly jac run bench/x11_close.jac
"""
import ctypes;
import os;
import re;
import struct;
import subprocess;
import sys;

glob CLIENT_MESSAGE: int = 33,
     SUBSTRUCTURE_MASK: int = (1 << 19) | (1 << 20),
     XEVENT_SIZE: int = 192;

"""Client windows titled exactly `title`, from `xwininfo -root -tree`.

Under GNOME the top-level window is mutter's frame, which carries the same title; the client
window inside it is the one to close.
"""
def find_windows(title: str) -> list[int] {
    out = subprocess.run(
        ["xwininfo", "-root", "-tree"], capture_output=True, text=True, timeout=30
    ).stdout;
    ids: list[int] = [];
    for line in out.splitlines() {
        found = re.match(r'\s*(0x[0-9a-f]+) "([^"]*)": \("([^"]*)"', line);
        if found
            and found.group(2) == title
            and found.group(3) != "mutter-x11-frames" {
            ids.append(int(found.group(1), 16));
        }
    }
    return ids;
}

def close_window(window: int) {
    x11 = ctypes.CDLL("libX11.so.6");
    x11.XOpenDisplay.restype = ctypes.c_void_p;
    x11.XInternAtom.restype = ctypes.c_ulong;
    x11.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int];
    x11.XDefaultRootWindow.restype = ctypes.c_ulong;
    x11.XDefaultRootWindow.argtypes = [ctypes.c_void_p];
    x11.XSendEvent.argtypes = [
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.c_int,
        ctypes.c_long,
        ctypes.c_char_p
    ];
    display = x11.XOpenDisplay(None);
    if not display {
        raise RuntimeError("cannot open the X display (is DISPLAY set?)");
    }
    atom = x11.XInternAtom(display, b"_NET_CLOSE_WINDOW", 0);
    # XClientMessageEvent on x86-64: type, serial, send_event, display, window, message_type,
    # format, data.l[5] (timestamp 0 = CurrentTime, source 2 = a pager or tool, like wmctrl).
    event = struct.pack(
        "<i4xQi4xQQQi4x5q", CLIENT_MESSAGE, 0, 1, 0, window, atom, 32, 0, 2, 0, 0, 0
    );
    event = event + bytes(XEVENT_SIZE - len(event));
    x11.XSendEvent(
        display, x11.XDefaultRootWindow(display), 0, SUBSTRUCTURE_MASK, event
    );
    x11.XFlush(ctypes.c_void_p(display));
    x11.XCloseDisplay(ctypes.c_void_p(display));
}

with entry {
    title = os.environ.get("WINDOW_TITLE", "Briefly");
    windows = find_windows(title);
    if not windows {
        print(f"no top-level window titled {title!r}");
        sys.exit(1);
    }
    for window in windows {
        close_window(window);
        print(hex(window));
    }
}
