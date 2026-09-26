from flask import Blueprint

blueprint = Blueprint("audio_analysis", __name__, url_prefix="/api")


@blueprint.get("/audio-uploads")
def get_audio_uploads():
    from ...results import assessments

    return assessments.get_audio_uploads()


@blueprint.post("/guest/audio-analysis")
def create_guest_audio_analysis():
    from ...audio_pipeline import pipeline

    return pipeline.create_guest_audio_analysis()


@blueprint.post("/audio-uploads")
def create_audio_upload():
    from ...audio_pipeline import pipeline

    return pipeline.create_audio_upload()


@blueprint.get("/audio-uploads/<int:upload_id>/analysis-dump")
def get_audio_analysis_dump(upload_id: int):
    from ...results import assessments

    return assessments.get_audio_analysis_dump(upload_id)
