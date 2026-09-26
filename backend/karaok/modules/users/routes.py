from flask import Blueprint

blueprint = Blueprint("users", __name__, url_prefix="/api")


@blueprint.get("/users")
def get_users():
    from ...admin import users

    return users.get_users()


@blueprint.patch("/users/me")
def update_profile():
    from ...users import profiles

    return profiles.update_profile()
