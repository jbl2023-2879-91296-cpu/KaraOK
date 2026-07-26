from flask import Blueprint

blueprint = Blueprint("system", __name__, url_prefix="/api")


@blueprint.get("/health")
def health():
    from ... import application

    return application.health()
