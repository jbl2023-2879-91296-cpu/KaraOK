from flask import Blueprint

blueprint = Blueprint("genre_settings", __name__, url_prefix="/api")


@blueprint.get("/genre-settings")
def get_genre_settings():
    from ... import application

    return application.get_genre_settings()


@blueprint.post("/genre-settings")
def save_genre_settings():
    from ... import application

    return application.save_genre_settings()
