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


def send_registration_otp(email: str, code: str) -> None:
    if not all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)):
        raise RuntimeError("SMTP is not configured; set SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, and SMTP_FROM")
    message = EmailMessage()
    message["Subject"] = "Email Verification OTP — Audio Evaluation System"
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(
        f"""Dear User,

Thank you for registering with our application.

Your One-Time Password (OTP) for email verification is:

**{code}**

This verification code is valid for **{OTP_MINUTES} minutes**. Please enter this code in the application to complete your registration.

For your security, do not share this OTP with anyone. Our team will never ask you for your verification code.

If you did not request this verification or believe you received this email in error, please disregard this message. No further action is required, and your account will not be activated unless the correct OTP is entered.

Thank you,

**The Audio Evaluation System Team**
"""
    )
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
        server.starttls()
        server.login(SMTP_USERNAME, SMTP_PASSWORD)
        server.send_message(message)


def send_temporary_password_email(email: str, temporary_password: str) -> None:
    if not all((SMTP_HOST, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM)):
        raise RuntimeError("SMTP is not configured")
    message = EmailMessage()
    message["Subject"] = "Your temporary KaraOK password"
    message["From"] = SMTP_FROM
    message["To"] = email
    message.set_content(
        f"""A password reset was requested for your KaraOK account.

Use this temporary password to sign in to the KaraOK application:

{temporary_password}

You will be required to choose a new password immediately after signing in. Do
not share this temporary password. If you did not request this reset, contact
the KaraOK administrator.
"""
    )
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as server:
        server.starttls()
        server.login(SMTP_USERNAME, SMTP_PASSWORD)
        server.send_message(message)
