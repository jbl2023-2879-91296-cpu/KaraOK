from flask import Blueprint

blueprint = Blueprint("users", __name__, url_prefix="/api")


@blueprint.get("/users")
def get_users():
    from ... import application

    return application.get_users()
