"""Score and recommend against the same technician genre target intervals."""
from .genre_profiles import load_genre_profiles
from .scoring import evaluate_features


def score_genre_values(values, genre):
    artifact = load_genre_profiles()
    profile = artifact.profile_for(genre)
    if profile.knob_preferences is None:
        return None
    metrics = {
        key: dict(observed_min=target.lower - target.robust_scale,
                  p05=target.lower, median=target.preferred, p95=target.upper,
                  observed_max=target.upper + target.robust_scale, unit=target.unit)
        for key, target in profile.metrics.items()
    }
    weights = dict(loudness=.3, bass=.25, treble=.2, sharpness=.15, flatness=.1)
    result = evaluate_features(values, dict(metrics=metrics, overall=dict(weights=weights)))
    result.update(method='technician_genre_reference', genre=profile.key,
                  reference_recording_count=profile.sample_count,
                  algorithm_version='1.1.0', quality_profile_version=artifact.profile_version,
                  quality_profile_checksum=artifact.artifact_checksum,
                  reference=dict(metrics=metrics, overall=dict(weights=weights)))
    for key, feature in result['features'].items():
        value = feature['value']
        target = profile.metrics[key]
        feature['direction'] = ('unavailable' if value is None else
                                'below' if value < target.lower else
                                'above' if value > target.upper else 'within')
        feature['target_lower'] = target.lower
        feature['target_upper'] = target.upper
    return result
