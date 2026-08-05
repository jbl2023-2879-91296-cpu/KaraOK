"""Explicit table capabilities for the Data Administration API."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TablePolicy:
    primary_key: str
    readable: bool = True
    create_fields: tuple[str, ...] = ()
    update_fields: tuple[str, ...] = ()
    deletable: bool = False
    hidden_fields: tuple[str, ...] = ()
    label: str = ""

    @property
    def creatable(self) -> bool:
        return bool(self.create_fields)

    @property
    def updatable(self) -> bool:
        return bool(self.update_fields)


TABLE_POLICIES: dict[str, TablePolicy] = {
    "user": TablePolicy(
        "user_id",
        update_fields=("is_active",),
        hidden_fields=("password", "profile_image"),
        label="Users",
    ),
    "genre_preset": TablePolicy(
        "preset_id",
        create_fields=("genre_name", "bass", "treble", "loudness", "sharpness", "flatness"),
        update_fields=("genre_name", "bass", "treble", "loudness", "sharpness", "flatness"),
        deletable=True,
        label="Genre presets",
    ),
    "audio_quality_threshold": TablePolicy(
        "threshold_id",
        create_fields=("threshold_name", "max_allowable_noise", "max_allowable_distortion", "min_quality_score"),
        update_fields=("threshold_name", "max_allowable_noise", "max_allowable_distortion", "min_quality_score"),
        deletable=True,
        label="Quality thresholds",
    ),
    "assessment": TablePolicy(
        "assessment_id",
        update_fields=("assessment_status",),
        deletable=True,
        label="Assessments",
    ),
    "audio_analysis_result": TablePolicy("result_id", label="Analysis results"),
    "user_genre_setting": TablePolicy(
        "setting_id",
        update_fields=("genre_name", "volume", "bass", "treble", "flatness", "sharpness"),
        deletable=True,
        label="User genre settings",
    ),
    "audio_upload": TablePolicy("upload_id", label="Audio uploads"),
    "audit_log": TablePolicy("audit_log_id", label="Audit log"),
    "api_request_log": TablePolicy("request_log_id", label="API request log"),
    # Session/verification tables appear in the catalog but their credential
    # hashes are intentionally unavailable through record endpoints.
    "refresh_token": TablePolicy("refresh_token_id", readable=False, hidden_fields=("token_hash",), label="Refresh tokens"),
    "revoked_access_token": TablePolicy("jti", readable=False, label="Revoked access tokens"),
    "registration_otp": TablePolicy("registration_id", readable=False, hidden_fields=("code_hash",), label="Registration verification"),
}


def table_policy(table: str) -> TablePolicy:
    try:
        return TABLE_POLICIES[table]
    except KeyError as error:
        raise ValueError("Table is not available to the Data Administration API") from error
