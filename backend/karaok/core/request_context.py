"""Request context implementation."""

from __future__ import annotations

from flask import request


def client_ip() -> str:
    return (request.remote_addr or "")[:45]
