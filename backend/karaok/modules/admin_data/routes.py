from __future__ import annotations

from flask import Blueprint, g, jsonify, request
from mysql.connector import Error, IntegrityError

from ...security.admin_data_auth import require_admin_data_key
from . import service


blueprint = Blueprint("admin_data", __name__, url_prefix="/api/admin/data")


def _audit(action: str, result: str, *, table: str | None = None, record_id: str | None = None) -> None:
    from ... import application

    numeric_id = int(record_id) if record_id and record_id.isdigit() else None
    actor = getattr(g, "authenticated_admin_actor", "local-admin")
    application.audit(
        action,
        result,
        resource_type=table or "admin_data",
        resource_id=numeric_id,
        details=f"actor={actor}",
    )


def _execute(operation, *args):
    try:
        return jsonify(operation(*args))
    except PermissionError as error:
        return jsonify({"error": str(error)}), 403
    except LookupError as error:
        return jsonify({"error": str(error)}), 404
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    except IntegrityError:
        return jsonify({"error": "The submitted values conflict with an existing or related record"}), 409
    except Error:
        return jsonify({"error": "Database operation failed"}), 500


@blueprint.get("/health")
@require_admin_data_key
def health():
    return _execute(service.health)


@blueprint.get("/tables")
@require_admin_data_key
def tables():
    return _execute(service.catalog)


@blueprint.get("/tables/<table>")
@require_admin_data_key
def table_details(table: str):
    return _execute(service.table_details, table)


@blueprint.get("/tables/<table>/records")
@require_admin_data_key
def records(table: str):
    return _execute(service.records, table, request.args.to_dict())


@blueprint.post("/tables/<table>/records")
@require_admin_data_key
def create_record(table: str):
    result = _execute(service.create_record, table, request.get_json(silent=True) or {})
    if isinstance(result, tuple):
        _audit("admin_data_created", "failure", table=table)
        return result
    payload = result.get_json()
    _audit("admin_data_created", "success", table=table, record_id=str(payload.get("id", "")))
    return result, 201


@blueprint.patch("/tables/<table>/records/<record_id>")
@require_admin_data_key
def update_record(table: str, record_id: str):
    result = _execute(service.update_record, table, record_id, request.get_json(silent=True) or {})
    if isinstance(result, tuple):
        _audit("admin_data_updated", "failure", table=table, record_id=record_id)
        return result
    _audit("admin_data_updated", "success", table=table, record_id=record_id)
    return result


@blueprint.delete("/tables/<table>/records/<record_id>")
@require_admin_data_key
def delete_record(table: str, record_id: str):
    data = request.get_json(silent=True) or {}
    result = _execute(service.delete_record, table, record_id, str(data.get("confirmation", "")))
    if isinstance(result, tuple):
        _audit("admin_data_deleted", "failure", table=table, record_id=record_id)
        return result
    if table == "assessment" and result.get_json().get("owner_user_id") is not None:
        from ... import application

        try:
            application.cleanup_audio_artifacts(
                int(result.get_json()["owner_user_id"]), int(record_id)
            )
        except (OSError, RuntimeError, ValueError):
            application.app.logger.exception(
                "Admin-deleted assessment artifact cleanup failed"
            )
    _audit("admin_data_deleted", "success", table=table, record_id=record_id)
    return result


@blueprint.get("/relationships")
@require_admin_data_key
def relationships():
    return _execute(service.relationships)


@blueprint.get("/analytics")
@require_admin_data_key
def analytics():
    return _execute(service.analytics)
