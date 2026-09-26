from flask import Blueprint

blueprint = Blueprint("audit", __name__, url_prefix="/api")


@blueprint.get("/audit-logs")
def get_audit_logs():
    from ...admin import logs

    return logs.get_audit_logs()


@blueprint.get("/request-logs")
def get_request_logs():
    from ...admin import logs

    return logs.get_request_logs()
