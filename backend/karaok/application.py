"""Flask composition, shared error handling, and legacy entry-point compatibility."""

from __future__ import annotations

import sys

from flask import g, jsonify
from mysql.connector import Error
from werkzeug.exceptions import HTTPException

from . import legacy_exports as _legacy_exports
from .compatibility import connect_legacy_overrides
from .core.audit import audit
from .core.runtime import app
from .request_logging import begin_api_request_log, complete_api_request_log
from .security.headers import apply_security_headers

# Existing scripts/tests import helpers from app; their implementations now live
# in the owning packages. Preserve that surface without reverse feature imports.
globals().update({name: getattr(_legacy_exports, name) for name in _legacy_exports.__all__})

app.before_request(begin_api_request_log)
app.after_request(complete_api_request_log)


@app.errorhandler(ValueError)
def handle_validation_error(error: ValueError):
    audit("input_validation_failed", "failure", user_id=getattr(g, "user_id", None), details=str(error))
    return jsonify({"error": str(error)}), 400


@app.errorhandler(Error)
def handle_database_error(error: Error):
    app.logger.exception("Database error")
    return jsonify({"error": "Database operation failed"}), 500


@app.errorhandler(HTTPException)
def handle_http_error(error: HTTPException):
    status_code = error.code or 500
    if status_code == 429:
        message = "Too many requests. Please wait before trying again."
    elif status_code >= 500:
        message = "Internal server error"
    else:
        message = error.description or error.name
    return jsonify({"error": message}), status_code


@app.errorhandler(Exception)
def handle_unexpected_error(error: Exception):
    app.logger.exception("Unhandled application error")
    return jsonify({"error": "Internal server error"}), 500


@app.after_request
def security_headers(response):
    return apply_security_headers(response)


for route_group in (
    system_routes,
    admin_data_routes,
    auth_routes,
    users_routes,
    assessments_routes,
    audio_analysis_routes,
    audit_routes,
    settings_recommendation_routes,
):
    app.register_blueprint(route_group)

connect_legacy_overrides(sys.modules[__name__])
