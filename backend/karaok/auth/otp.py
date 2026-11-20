"""Issue, rotate, and consume email-bound, single-use challenges."""

import hmac
import secrets
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from hashlib import sha256

import karaok.core.config as config


_TABLES = {"registration": "registration_otp", "password_reset": "password_reset_otp"}


@dataclass(frozen=True)
class Challenge:
    challenge_id: str
    expires_at: int
    resend_available_at: int
    code: str | None = None
    server_time: int = 0


class ResendTooSoon(Exception):
    def __init__(self, retry_after: int):
        super().__init__(retry_after)
        self.retry_after = retry_after


def code_digest(purpose, challenge_id, email, code):
    if len(config.JWT_SECRET) < 32:
        raise RuntimeError("JWT_SECRET must be configured before issuing OTP challenges")
    return hmac.new(
        config.JWT_SECRET.encode(), f"{purpose}|{challenge_id}|{email}|{code}".encode(), sha256
    ).hexdigest()


def _utc(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).replace(tzinfo=None)


def _epoch(date):
    return int(date.replace(tzinfo=timezone.utc).timestamp())


def _new_challenge(now, challenge_id=None, code=None):
    return Challenge(challenge_id or secrets.token_hex(16), now + config.OTP_MINUTES * 60,
                     now + config.OTP_RESEND_COOLDOWN_SECONDS, code, now)


def decoy_challenge(challenge_id=None):
    return _new_challenge(int(time.time()), challenge_id)


def challenge_payload(challenge):
    return {"challenge_id": challenge.challenge_id, "expires_at": challenge.expires_at,
            "resend_available_at": challenge.resend_available_at, "server_time": challenge.server_time}


def issue_challenge(cursor, *, purpose, user_id, email, challenge_id=None):
    table = _TABLES[purpose]
    cursor.execute(
        f"""SELECT challenge_id, last_sent_at, send_count_window_start, send_count, code_hash
            FROM {table} WHERE user_id = %s FOR UPDATE""",
        (user_id,),
    )
    current = cursor.fetchone()
    if challenge_id and (not current or current["challenge_id"] != challenge_id):
        return decoy_challenge(challenge_id)
    now = int(time.time())
    start, count = now, 0
    if current:
        start = _epoch(current["send_count_window_start"])
        count = current["send_count"]
        next_send = _epoch(current["last_sent_at"]) + config.OTP_RESEND_COOLDOWN_SECONDS
        if now >= start + 3600:
            start, count = now, 0
        elif count >= config.OTP_MAX_SENDS_PER_EMAIL_PER_HOUR:
            next_send = max(next_send, start + 3600)
        if now < next_send:
            raise ResendTooSoon(next_send - now)
    challenge_id = challenge_id or secrets.token_hex(16)
    while True:
        code = f"{secrets.randbelow(1_000_000):06d}"
        digest = code_digest(purpose, challenge_id, email, code)
        if not current or current["code_hash"] != code_digest(
            purpose, current["challenge_id"], email, code
        ):
            break
    challenge = _new_challenge(now, challenge_id, code)
    cursor.execute(
        f"""INSERT INTO {table} (user_id, email, challenge_id, code_hash, expires_at,
                                  last_sent_at, send_count_window_start, send_count)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE email=%s, challenge_id=%s, code_hash=%s, expires_at=%s,
                last_sent_at=%s, send_count_window_start=%s, send_count=%s, attempts=0""",
        (user_id,) + (email, challenge_id, digest, _utc(challenge.expires_at),
                      _utc(now), _utc(start), count + 1) * 2,
    )
    return challenge


def resend_challenge(cursor, *, purpose, user_id, email, challenge_id):
    return issue_challenge(cursor, purpose=purpose, user_id=user_id,
                           email=email, challenge_id=challenge_id)


def verify_challenge(cursor, *, purpose, challenge_id, email, code):
    table = _TABLES[purpose]
    # Callers lock the user row first, consistently with issuing and resending.
    cursor.execute(
        f"""SELECT otp.user_id, otp.code_hash
            FROM {table} otp JOIN user ON user.user_id = otp.user_id
            WHERE otp.challenge_id = %s AND otp.email = %s AND user.email = %s
              AND otp.expires_at > UTC_TIMESTAMP() AND otp.attempts < %s
            FOR UPDATE""",
        (challenge_id, email, email, config.OTP_MAX_VERIFY_ATTEMPTS),
    )
    row = cursor.fetchone()
    if not row:
        return None
    if not secrets.compare_digest(row["code_hash"], code_digest(purpose, challenge_id, email, code)):
        cursor.execute(f"UPDATE {table} SET attempts = attempts + 1 WHERE user_id = %s", (row["user_id"],))
        return None
    cursor.execute(f"DELETE FROM {table} WHERE user_id = %s", (row["user_id"],))
    return row["user_id"]
