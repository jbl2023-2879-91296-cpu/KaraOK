from flask import Blueprint

blueprint = Blueprint("auth", __name__, url_prefix="/api/auth")


@blueprint.post("/register")
def register():
    from ... import application

    return application.register()


@blueprint.post("/register/verify")
def verify_registration():
    from ... import application

    return application.verify_registration()


@blueprint.post("/login")
def login():
    from ... import application

    return application.login()


@blueprint.post("/refresh")
def refresh():
    from ... import application

    return application.refresh()


@blueprint.post("/logout")
def logout():
    from ... import application

    return application.logout()


@blueprint.post("/forgot-password")
def forgot_password():
    from ... import application

    return application.forgot_password()


@blueprint.post("/change-password")
def change_password():
    from ... import application

    return application.change_password()
