# Media-session coverage record

Source sync commit: `b1bbc4d5c756998dd6ffa56f5e6d77efdb2d9803`.

Covered file: `Vendor/mediaremote-adapter/src/adapter/stream.m`.
SHA-256: `70c142c13f4c371597b8e79cb3094caeef4cbc8511b89c1b7ced3baf4f65b60e`.

Covered symbols: `requestNowPlayingApplicationPID`, `requestNowPlayingParentApplicationBundleIdentifier`, `requestNowPlayingApplicationIsPlaying`, `requestNowPlayingInfo`, `requestAll`, `resetAll`, and the no-process reset branches. Notification wiring and `refreshAll` are covered by native regression checks; the TLA+ model covers the no-process retirement path specifically.

Observation tags model provenance of cached values; they do not imply that every partial cache is published. The metadata reply must satisfy both guards. Field replies must satisfy their session guard. Revalidate this correspondence before advancing the source sync commit.
