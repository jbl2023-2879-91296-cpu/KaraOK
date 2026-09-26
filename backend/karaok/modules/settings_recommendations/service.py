"""Compatibility exports for recommendation and amplifier-profile callers."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Mapping

import jwt

from audio_thresholds import (
    load_control_priors,
    load_genre_profiles,
    load_thresholds,
    normalize_genre,
)
from settings_recommendations import (
    ALGORITHM_VERSION,
    AmplifierScale,
    KnobAdjustment,
    KnobSettings,
    RecommendationRequest,
    SafetySignals,
    SettingsRecommendation,
    generate_recommendation,
)

from ...core.validation import bounded_number
from ...core.config import JWT_SECRET
from ...core.database import get_db
from karaok.results.profiles import PROFILE_FIELDS
from karaok.results.profiles import SCALE_FIELDS
from karaok.core.recommendation_contracts import KNOB_NAMES
from karaok.audio_pipeline.pipeline import GUEST_VERIFICATION_AUDIENCE
from karaok.audio_pipeline.pipeline import GUEST_VERIFICATION_KIND
from karaok.audio_pipeline.pipeline import GUEST_TOKEN_CLAIMS
from karaok.audio_pipeline.pipeline import GENRE_ARTIFACT_UNAVAILABLE_MESSAGE
from karaok.audio_pipeline.pipeline import MISSING_GENRE_PROFILE_MESSAGE
from karaok.core.recommendation_contracts import ConflictError
from karaok.core.recommendation_contracts import GuestVerificationContext
from karaok.core.recommendation_contracts import SuggestionContext
from karaok.core.recommendation_contracts import _strict_number
from karaok.core.recommendation_contracts import _json_object
from karaok.core.recommendation_contracts import _amplifier_scale
from karaok.core.recommendation_contracts import _knob_settings
from karaok.core.recommendation_contracts import _positive_identifier
from karaok.core.recommendation_contracts import _same_scale
from karaok.core.recommendation_contracts import _quantized_step_index
from karaok.core.recommendation_contracts import _same_positions
from karaok.core.recommendation_contracts import _stored_scale
from karaok.core.recommendation_contracts import validate_profile_scale_snapshot
from karaok.core.recommendation_contracts import validate_authenticated_verification_binding
from karaok.audio_pipeline.pipeline import parse_guest_verification_token
from karaok.audio_pipeline.pipeline import issue_guest_verification_token
from karaok.audio_pipeline.pipeline import parse_suggestion_form
from karaok.audio_pipeline.pipeline import _unavailable_recommendation
from karaok.audio_pipeline.pipeline import build_recommendation
from karaok.results.database import _connection
from karaok.results.profiles import _finite_number
from karaok.results.profiles import _name
from karaok.results.profiles import _scale
from karaok.results.profiles import _positions
from karaok.core.recommendation_contracts import _decoded_json
from karaok.core.recommendation_contracts import _json_safe
from karaok.core.recommendation_contracts import _score_comparison
from karaok.core.recommendation_contracts import recommendation_payload
from karaok.results.profiles import _profile_response
from karaok.core.recommendation_contracts import _recommendation_response
from karaok.core.recommendation_contracts import stored_recommendation_payload
from karaok.results.profiles import _select_profile
from karaok.core.recommendation_contracts import get_profile_metadata
from karaok.results.profiles import list_amplifier_profiles
from karaok.results.profiles import get_amplifier_profile
from karaok.results.profiles import create_amplifier_profile
from karaok.results.profiles import update_amplifier_profile
from karaok.results.profiles import delete_amplifier_profile
from karaok.results.recommendations import _recommendation_select
from karaok.results.recommendations import get_owned_recommendation
from karaok.results.recommendations import mark_recommendation_applied


import sys
from ...compatibility import connect_legacy_overrides
connect_legacy_overrides(sys.modules[__name__])
