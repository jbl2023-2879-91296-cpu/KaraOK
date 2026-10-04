# Versioning

When recommending or updating an app version, inspect the versioned artifacts in
`dist/` and use the highest existing semantic version as the baseline, including
debug builds. Choose the next semantic version according to the change scope and
increment the highest existing build number. Treat `dist/` as authoritative when
its versions differ from `frontend/pubspec.yaml`.
