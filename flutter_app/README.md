# Natalo Petshop Flutter

Flutter client for Natalo Petshop.

## Social video registry observation

The social video registry observation package is passive diagnostics only. It
detects distinct live controller identities for the same social post; it does
not reduce controller count, transfer playback ownership, or issue player
commands.

Use these exact compile-time build modes:

```text
Default/rollback: --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=false
Canary: --dart-define=SOCIAL_VIDEO_REGISTRY_OBSERVE=true
```

The default is disabled. Changing the value requires a new build or launch
because the setting is read from `bool.fromEnvironment` at process startup.

See the
[social video registry observation runbook](../docs/operations/social-video-registry-observation.md)
for canary enablement, data-minimized metrics, privacy approval, device
validation, monitoring, and rollback.

## Getting started

Flutter setup and development guidance is available in the
[Flutter documentation](https://docs.flutter.dev/).
