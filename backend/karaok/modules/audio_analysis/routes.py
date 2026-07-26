from flask import Blueprint

blueprint = Blueprint("audio_analysis", __name__, url_prefix="/api")


@blueprint.get("/audio-uploads")
def get_audio_uploads():
    from ... import application

    return application.get_audio_uploads()


@blueprint.post("/guest/audio-analysis")
def create_guest_audio_analysis():
    from ... import application

    return application.create_guest_audio_analysis()


@blueprint.post("/audio-uploads")
def create_audio_upload():
    from ... import application

    return application.create_audio_upload()


@blueprint.get("/audio-uploads/<int:upload_id>/analysis-dump")
def get_audio_analysis_dump(upload_id: int):
    from ... import application

    return application.get_audio_analysis_dump(upload_id)
