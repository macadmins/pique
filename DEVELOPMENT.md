# Development notes

## Provisioning profiles

The release workflow's "Install provisioning profiles" step requires two provisioning profiles prepared in the Apple Developer Portal — one for the Pique app and one for the PiquePreview extension. Both profiles should be of type "macOS App Development" and reference the matching bundle identifiers.

Download both profiles to your Mac, then extract their `Name` (the human-readable name from the portal) and a base64 blob for each.

### Extract profile names

These go into the `*_NAME_MAOS` secrets:

```sh
security cms -D -i ~/Downloads/iomacadminspiqueprovisioning.provisionprofile | plutil -extract Name raw -
security cms -D -i ~/Downloads/iomacadminspiquePiquePreviewprovisioning.provisionprofile | plutil -extract Name raw -
```

### Encode profiles as base64

These go into the `*_BASE64_MAOS` secrets:

```sh
base64 -i ~/Downloads/iomacadminspiqueprovisioning.provisionprofile | pbcopy          # → PIQUE_PROVISION_PROFILE_BASE64_MAOS
base64 -i ~/Downloads/iomacadminspiquePiquePreviewprovisioning.provisionprofile | pbcopy   # → PIQUE_PREVIEW_PROVISION_PROFILE_BASE64_MAOS
```

### Add the four secrets

In GitHub → **Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `PIQUE_PROVISION_PROFILE_NAME_MAOS` | exact `Name` from the Pique profile |
| `PIQUE_PREVIEW_PROVISION_PROFILE_NAME_MAOS` | exact `Name` from the PiquePreview profile |
| `PIQUE_PROVISION_PROFILE_BASE64_MAOS` | base64 of the Pique profile |
| `PIQUE_PREVIEW_PROVISION_PROFILE_BASE64_MAOS` | base64 of the PiquePreview profile |
