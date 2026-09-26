"""Feature-flagged routes for amplifier profiles and saved recommendations."""

from __future__ import annotations

from functools import wraps

from flask import Blueprint, g, jsonify
from mysql.connector import IntegrityError

from ...auth.access import require_auth
from ...core.audit import audit
from ...core.config import SETTINGS_RECOMMENDATIONS_ENABLED
from ...core.validation import json_body
from ...core import recommendation_contracts as contracts
from ...results import profiles, recommendations


blueprint = Blueprint("settings_recommendations", __name__, url_prefix="/api")


def _feature_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not SETTINGS_RECOMMENDATIONS_ENABLED:
            return jsonify({"error": "Not found"}), 404
        return view(*args, **kwargs)

    return wrapped


def _require_user(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        return require_auth("user")(view)(*args, **kwargs)

    return wrapped


def _service_call(operation, *args):
    try:
        return operation(*args)
    except contracts.ConflictError as error:
        return jsonify({"error": str(error)}), 409
    except LookupError as error:
        return jsonify({"error": str(error)}), 404
    except IntegrityError:
        return jsonify({"error": "An amplifier profile with that name already exists"}), 409


def _body():
    return json_body()


def _audit(action: str, resource_type: str, resource_id: int | None) -> None:
    audit(
        action,
        "success",
        user_id=g.user_id,
        resource_type=resource_type,
        resource_id=resource_id,
    )


@blueprint.get("/settings-profile-metadata")
@_feature_required
def profile_metadata():
    return jsonify(contracts.get_profile_metadata())


@blueprint.get("/amplifier-profiles")
@_feature_required
@_require_user
def list_profiles():
    return jsonify(profiles.list_amplifier_profiles(g.user_id))


@blueprint.post("/amplifier-profiles")
@_feature_required
@_require_user
def create_profile():
    result = _service_call(profiles.create_amplifier_profile, g.user_id, _body())
    if isinstance(result, tuple):
        return result
    _audit("amplifier_profile_created", "amplifier_profile", result["id"])
    return jsonify(result), 201


@blueprint.get("/amplifier-profiles/<int:profile_id>")
@_feature_required
@_require_user
def get_profile(profile_id: int):
    result = _service_call(
        profiles.get_amplifier_profile,
        g.user_id,
        profile_id,
    )
    if isinstance(result, tuple):
        return result
    return jsonify(result)


@blueprint.patch("/amplifier-profiles/<int:profile_id>")
@_feature_required
@_require_user
def update_profile(profile_id: int):
    result = _service_call(
        profiles.update_amplifier_profile,
        g.user_id,
        profile_id,
        _body(),
    )
    if isinstance(result, tuple):
        return result
    _audit("amplifier_profile_updated", "amplifier_profile", profile_id)
    return jsonify(result)


@blueprint.delete("/amplifier-profiles/<int:profile_id>")
@_feature_required
@_require_user
def delete_profile(profile_id: int):
    result = _service_call(profiles.delete_amplifier_profile, g.user_id, profile_id)
    if isinstance(result, tuple):
        return result
    _audit("amplifier_profile_deleted", "amplifier_profile", profile_id)
    return jsonify(result)


@blueprint.get("/settings-recommendations/<int:recommendation_id>")
@_feature_required
@_require_user
def get_recommendation(recommendation_id: int):
    result = _service_call(
        recommendations.get_owned_recommendation,
        g.user_id,
        recommendation_id,
    )
    if isinstance(result, tuple):
        return result
    return jsonify(result)


@blueprint.post("/settings-recommendations/<int:recommendation_id>/apply")
@_feature_required
@_require_user
def apply_recommendation(recommendation_id: int):
    result = _service_call(
        recommendations.mark_recommendation_applied,
        g.user_id,
        recommendation_id,
    )
    if isinstance(result, tuple):
        return result
    _audit("settings_recommendation_applied", "settings_recommendation", recommendation_id)
    return jsonify(result)
