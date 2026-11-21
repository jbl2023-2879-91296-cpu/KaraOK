"""Reserve bounded capacity before a transaction and deliver only after commit."""

from concurrent.futures import ThreadPoolExecutor
from threading import BoundedSemaphore

from karaok.core.runtime import app


_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="auth-mail")
_slots = BoundedSemaphore(50)


class MailReservation:
    def __enter__(self):
        self.available = _slots.acquire(blocking=False)
        self.submitted = False
        return self

    def __exit__(self, *_):
        if self.available and not self.submitted:
            _slots.release()

    def submit(self, send, *, description):
        if not self.available or self.submitted:
            return False

        def deliver():
            try:
                send()
            except Exception:
                app.logger.exception("Auth email delivery failed: %s", description)
            finally:
                _slots.release()

        try:
            _executor.submit(deliver)
        except RuntimeError:
            app.logger.exception("Auth mail queue unavailable")
            return False
        self.submitted = True
        return True


def enqueue_mail(send, *, description):
    with MailReservation() as reservation:
        return reservation.submit(send, description=description)
