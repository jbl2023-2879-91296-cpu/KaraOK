from flask import Blueprint

blueprint = Blueprint("assessments", __name__, url_prefix="/api")


@blueprint.get("/audio-tests")
def get_audio_tests():
    from ... import application

    return application.get_audio_tests()


@blueprint.get("/audio-tests/<int:test_id>")
def get_audio_test(test_id: int):
    from ... import application

    return application.get_audio_test(test_id)


@blueprint.post("/audio-tests")
def create_audio_test():
    from ... import application

    return application.create_audio_test()


@blueprint.delete("/audio-tests/<int:test_id>")
def delete_audio_test(test_id: int):
    from ... import application

    return application.delete_audio_test(test_id)


@blueprint.get("/audio-tests/<int:test_id>/visualizations/<kind>")
def get_audio_visualization(test_id: int, kind: str):
    from ... import application

    return application.get_audio_visualization(test_id, kind)
