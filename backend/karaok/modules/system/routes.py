from flask import Blueprint

blueprint = Blueprint("system", __name__, url_prefix="/api")


@blueprint.get("/health")
def health():
    from ...system import health

    return health.health()
