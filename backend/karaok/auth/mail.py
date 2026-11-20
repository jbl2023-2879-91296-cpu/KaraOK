"""Mail implementation."""

from __future__ import annotations

from email.message import EmailMessage
from karaok.core.config import OTP_MINUTES
from karaok.core.config import SMTP_FROM
from karaok.core.config import SMTP_HOST
from karaok.core.config import SMTP_PASSWORD
from karaok.core.config import SMTP_PORT
from karaok.core.config import SMTP_USERNAME
import smtplib


def _send(email: str, subject: str, content: str) -> None:
    if not all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)):
        raise RuntimeError("SMTP is not configured")
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(content)
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
        server.starttls()
        server.login(SMTP_USERNAME, SMTP_PASSWORD)
        server.send_message(message)


def send_registration_otp(email: str, code: str) -> None:
    _send(email, "Your KaraOK verification code",
          f"Your KaraOK verification code is {code}.\n\n"
          f"It expires in {OTP_MINUTES} minutes. Do not share this code. "
          "If you did not request verification, you can ignore this message.")


def send_reset_otp(email: str, code: str) -> None:
    _send(email, "Your KaraOK password reset code",
          f"Your KaraOK password reset code is {code}.\n\n"
          f"It expires in {OTP_MINUTES} minutes. Do not share this code. "
          "If you did not request a reset, you can ignore this message.")


def send_account_exists_notice(email: str) -> None:
    _send(email, "KaraOK account registration request",
          "Someone tried to create a KaraOK account with this email. "
          "If it was you, log in or use Forgot password.")


def send_password_changed_notice(email: str) -> None:
    _send(email, "Your KaraOK password has changed",
          "Your KaraOK password was reset. If you did not make this change, "
          "contact the KaraOK administrator.")
