"""Worker-shared and request-scoped abuse limits for authentication."""

import math
import re
import time
from dataclasses import dataclass, replace
from hashlib import sha256
from threading import Lock
from typing import Callable, Protocol

from flask import g, jsonify, request
from mysql.connector import Error

import karaok.core.config as config
import karaok.core.database as database
from karaok.core.runtime import app


_OTP_WINDOW_SECONDS = 3600
_DEVICE_ID_PATTERN = re.compile(r"[0-9a-f]{32}")


@dataclass(frozen=True)
class ThrottleDecision:
    allowed: bool
    retry_after: int = 0


@dataclass(frozen=True)
class _State:
    window_started_at: float
    hits: int
    strikes: int
    locked_until: float
    last_seen_at: float


def _advance(state, now, limit, window, fixed_lock):
    state = state or _State(now, 0, 0, 0, now)
    now = max(now, state.last_seen_at)
    if now < state.locked_until:
        return replace(state, last_seen_at=now), ThrottleDecision(
            False, math.ceil(state.locked_until - now)
        )
    strikes = 0 if now - state.last_seen_at >= config.AUTH_STRIKE_RESET_SECONDS else state.strikes
    if state.locked_until or now - state.window_started_at >= window:
        state = _State(now, 0, strikes, 0, now)
    hits = state.hits + 1
    if hits <= limit:
        return replace(state, hits=hits, strikes=strikes, last_seen_at=now), ThrottleDecision(True)
    delay = fixed_lock or (
        config.AUTH_LOCKOUT_REPEAT_SECONDS if strikes else config.AUTH_LOCKOUT_FIRST_SECONDS
    )
    return _State(now, hits, min(strikes + 1, 255), now + delay, now), ThrottleDecision(False, delay)


def _schedule_otp(state, now):
    state = state or _State(now, 0, 0, 0, now)
    now = max(now, state.last_seen_at)
    start, hits = state.window_started_at, state.hits
    if now >= start + _OTP_WINDOW_SECONDS:
        start, hits = now, 0
    available = state.locked_until
    if hits >= config.OTP_MAX_SENDS_PER_EMAIL_PER_HOUR:
        available = max(available, start + _OTP_WINDOW_SECONDS)
    if now < available:
        return state, ThrottleDecision(False, math.ceil(available - now))
    return (
        _State(start, hits + 1, 0, now + config.OTP_RESEND_COOLDOWN_SECONDS, now),
        ThrottleDecision(True),
    )


class ThrottleStore(Protocol):
    def update(self, key: str, now: float, advance) -> ThrottleDecision: ...
    def update_many(self, keys: tuple[str, ...], now: float, advance) -> ThrottleDecision: ...


class MemoryThrottleStore:
    def __init__(self):
        self._states = {}
        self._lock = Lock()

    def update(self, key, now, advance):
        with self._lock:
            state, decision = advance(self._states.get(key), now)
            self._states[key] = state
            return decision

    def update_many(self, keys, now, advance):
        with self._lock:
            states = {key: self._states.get(key) for key in keys}
            updates, decision = advance(states, now)
            self._states.update(updates)
            return decision


class MySqlThrottleStore:
    def update(self, key, now, advance):
        def advance_one(states, timestamp):
            state, decision = advance(states[key], timestamp)
            return {key: state}, decision

        return self.update_many((key,), now, advance_one)

    def update_many(self, keys, now, advance):
        connection = database.get_db()
        try:
            cursor = connection.cursor()
            try:
                states = {}
                # Acquire overlapping sender locks in a consistent order across workers.
                for key in sorted(keys):
                    cursor.execute(
                        """INSERT INTO auth_throttle (throttle_key, window_started_at, last_seen_at)
                           VALUES (%s, %s, %s)
                           ON DUPLICATE KEY UPDATE throttle_key = throttle_key""",
                        (key, now, now),
                    )
                    cursor.execute(
                        """SELECT window_started_at, hits, strikes, locked_until, last_seen_at
                           FROM auth_throttle WHERE throttle_key = %s FOR UPDATE""",
                        (key,),
                    )
                    states[key] = _State(*cursor.fetchone())
                updates, decision = advance(states, now)
                if not updates:
                    connection.rollback()
                    return decision
                for key, state in updates.items():
                    cursor.execute(
                        """UPDATE auth_throttle
                           SET window_started_at=%s, hits=%s, strikes=%s, locked_until=%s, last_seen_at=%s
                           WHERE throttle_key=%s""",
                        (state.window_started_at, state.hits, state.strikes,
                         state.locked_until, state.last_seen_at, key),
                    )
                connection.commit()
                return decision
            finally:
                cursor.close()
        finally:
            connection.close()


def _fail_open(operation: Callable[[], ThrottleDecision]) -> ThrottleDecision:
    try:
        return operation()
    except Error:
        app.logger.exception("Auth throttle database unavailable")
        return ThrottleDecision(True)


class AuthThrottle:
    def __init__(self, store: ThrottleStore, clock: Callable[[], float] = time.time):
        self.store = store
        self.clock = clock

    def check(self, action, *, email, device_id, ip, burst_limit=None,
              burst_window=None, fixed_lock_seconds=None):
        now = self.clock()

        def hit(key, limit, window, fixed):
            return self.store.update(sha256(key.encode()).hexdigest(), now,
                                     lambda state, now: _advance(state, now, limit, window, fixed))

        def check_limits():
            if ip != "*":
                ceiling = hit(f"{action}|ipceil:{ip}", config.AUTH_IP_CEILING_PER_MINUTE, 60, 60)
                if not ceiling.allowed:
                    return ceiling
            return hit(
                f"{action}|dev:{device_id or 'ip:' + ip}|{email or '-'}",
                burst_limit or config.AUTH_BURST_LIMIT,
                burst_window or config.AUTH_BURST_WINDOW_SECONDS,
                fixed_lock_seconds,
            )

        return _fail_open(check_limits)

    def reserve_otp_send(self, purpose, email):
        key = sha256(f"otp|{purpose}|{email}".encode()).hexdigest()
        return _fail_open(lambda: self.store.update(key, self.clock(), _schedule_otp))

    def reserve_otp_sender(self, *, device_id: str | None, ip: str) -> ThrottleDecision:
        identity = device_id if _DEVICE_ID_PATTERN.fullmatch(device_id or "") else f"ip:{ip}"
        device_key = sha256(f"otp-sender|device:{identity}".encode()).hexdigest()
        ip_key = sha256(f"otp-sender|ip:{ip}".encode()).hexdigest()
        limits = {
            device_key: config.OTP_MAX_SENDS_PER_DEVICE_PER_HOUR,
            ip_key: config.OTP_MAX_SENDS_PER_IP_PER_HOUR,
        }

        def reserve(states, now):
            updates = {}
            retry_after = 0
            for key, limit in limits.items():
                state = states[key]
                timestamp = max(now, state.last_seen_at) if state else now
                if (
                    not state
                    or state.hits == 0
                    or timestamp >= state.window_started_at + _OTP_WINDOW_SECONDS
                ):
                    state = _State(timestamp, 0, 0, 0, timestamp)
                if state.hits >= limit:
                    reset_at = state.window_started_at + _OTP_WINDOW_SECONDS
                    retry_after = max(retry_after, math.ceil(reset_at - timestamp))
                updates[key] = replace(state, hits=state.hits + 1, last_seen_at=timestamp)
            if retry_after:
                return {}, ThrottleDecision(False, retry_after)
            return updates, ThrottleDecision(True)

        return _fail_open(lambda: self.store.update_many(tuple(limits), self.clock(), reserve))


def request_device_id():
    value = request.headers.get("X-KaraOK-Device", "")
    return value if _DEVICE_ID_PATTERN.fullmatch(value) else None


def throttled_response(decision):
    seconds = max(1, decision.retry_after)
    g.karaok_retry_after = seconds
    if seconds < 60:
        duration = f"{seconds} {'second' if seconds == 1 else 'seconds'}"
    else:
        minutes = math.ceil(seconds / 60)
        duration = f"{minutes} {'minute' if minutes == 1 else 'minutes'}"
    return (
        jsonify(error=f"Too many attempts. Try again in {duration}.", retry_after=seconds),
        429,
        {"Retry-After": str(seconds)},
    )


auth_throttle = AuthThrottle(MySqlThrottleStore())
