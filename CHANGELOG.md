## 0.0.4

* Fix [SDKPC024]: Update Documentation on `Layer Overview`, `Layer Responsibilities`, `CallEngine SSOT Rules`, `Lifecycle/data flow`, `Tracing and Debug Guide` and `Architecture Rules`

## 0.0.3

* Fix [SDKPC023]: Reconnect lifecycle — `_restoreMediaSession` in `CallEngine` now triggers during both `connected` and `reconnecting` phases, preventing media session restoration from being skipped while a reconnect is in progress.
* Fix [SDKPC023]: `hasRemoteParticipant` in `SDKConnectRuntimeState` no longer reports `true` during the `connecting` phase; remote participant presence is now only flagged on `connected` or `reconnecting`.

## 0.0.2

* Refactor: SDKConnect public API is now focused on media/session lifecycle only.
* Breaking: removed invitation lifecycle methods from SDK surfaces:
	* `SDKConnect.acceptCall` and `SDKConnect.rejectCall`
	* `VoiceCallSdk.acceptCall` and `VoiceCallSdk.rejectCall`
	* `VideoCallSdk.acceptCall` and `VideoCallSdk.rejectCall`
* Documentation: updated consumer-facing lifecycle states/events, widget callbacks/fallback behavior, and ownership boundaries.

## 0.0.1

* TODO: Describe initial release.
