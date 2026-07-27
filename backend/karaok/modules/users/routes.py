from flask import Blueprint

blueprint = Blueprint("users", __name__, url_prefix="/api")


@blueprint.get("/users")
def get_users():
    from ... import application

    return application.get_users()


@blueprint.patch("/users/me")
def update_profile():
    from ... import application

    return application.update_profile()
