from flask import Blueprint

blueprint = Blueprint("auth", __name__, url_prefix="/api/auth")


@blueprint.post("/register")
def register():
    from ...auth import accounts

    return accounts.register()


@blueprint.post("/register/verify")
def verify_registration():
    from ...auth import accounts

    return accounts.verify_registration()


@blueprint.post("/register/resend")
def resend_registration():
    from ...auth import accounts

    return accounts.resend_registration()


@blueprint.post("/login")
def login():
    from ...auth import accounts

    return accounts.login()


@blueprint.post("/refresh")
def refresh():
    from ...auth import accounts

    return accounts.refresh()


@blueprint.post("/logout")
def logout():
    from ...auth import accounts

    return accounts.logout()


@blueprint.post("/forgot-password")
def forgot_password():
    from ...auth import accounts

    return accounts.forgot_password()


@blueprint.post("/forgot-password/resend")
def resend_password_reset():
    from ...auth import accounts

    return accounts.resend_password_reset()


@blueprint.post("/forgot-password/reset")
def reset_password():
    from ...auth import accounts

    return accounts.reset_password()


@blueprint.post("/change-password")
def change_password():
    from ...auth import accounts

    return accounts.change_password()
