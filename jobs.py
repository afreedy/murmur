"""Private-pipe jobs with cancellation that also interrupts active Python work."""
from contextlib import contextmanager
import json
import os
import queue
import signal
import sys
import threading


class Cancelled(Exception):
    pass


class Jobs:
    def __init__(self):
        self.queue = queue.Queue()
        self.pending = {}
        self.lock = threading.Lock()
        self.active = None
        signal.signal(signal.SIGUSR1, self.interrupt)
        threading.Thread(target=self.read, daemon=True).start()

    def interrupt(self, *_):
        if self.active is not None and self.active.is_set():
            raise Cancelled()

    def read(self):
        for line in sys.stdin:
            try:
                job = json.loads(line)
            except (ValueError, TypeError):
                self.queue.put(line)
                continue
            if isinstance(job, dict) and isinstance(job.get('id'), str):
                interrupt = False
                with self.lock:
                    if job.get('type') == 'cancel':
                        event = self.pending.get(job['id'])
                        if event is not None and not event.is_set():
                            event.set()
                            interrupt = event is self.active
                    # Prepare and format can share an ID; only inference is cancellable.
                    elif job.get('type') != 'prepare':
                        self.pending.setdefault(job['id'], threading.Event())
                if job.get('type') == 'cancel':
                    if interrupt:
                        os.kill(os.getpid(), signal.SIGUSR1)
                    continue
            self.queue.put(line)
        self.queue.put(None)

    def __iter__(self):
        while (line := self.queue.get()) is not None:
            yield line

    def discard(self, ident):
        if not isinstance(ident, str):
            return
        with self.lock:
            self.pending.pop(ident, None)

    @contextmanager
    def processing(self, ident):
        event = None
        try:
            with self.lock:
                event = self.pending.get(ident, threading.Event())
                self.active = event
            if event.is_set():
                raise Cancelled()
            yield
        finally:
            self.active = None
            with self.lock:
                if self.pending.get(ident) is event:
                    self.pending.pop(ident, None)
