"""Amplifier profile and persisted recommendation feature module."""

from .service import (
    GuestVerificationContext,
    SuggestionContext,
    build_recommendation,
    create_amplifier_profile,
    delete_amplifier_profile,
    get_amplifier_profile,
    get_owned_recommendation,
    get_profile_metadata,
    issue_guest_verification_token,
    list_amplifier_profiles,
    mark_recommendation_applied,
    parse_guest_verification_token,
    parse_suggestion_form,
    update_amplifier_profile,
)

__all__ = [
    "GuestVerificationContext",
    "SuggestionContext",
    "build_recommendation",
    "create_amplifier_profile",
    "delete_amplifier_profile",
    "get_amplifier_profile",
    "get_owned_recommendation",
    "get_profile_metadata",
    "issue_guest_verification_token",
    "list_amplifier_profiles",
    "mark_recommendation_applied",
    "parse_guest_verification_token",
    "parse_suggestion_form",
    "update_amplifier_profile",
]
