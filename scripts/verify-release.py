from pathlib import Path
import hashlib, json, plistlib, re
root = Path(__file__).resolve().parents[1]
m = json.loads((root / 'release-manifest.json').read_text())
for name, expected in m['files'].items():
    actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
    assert actual == expected, f"Frozen source changed: {name}"
    print(f"verified {name} {actual}")
assert m['version'] == '1.0.1'
assert m['channel'] == 'desktop_sdk'
assert f'channel = "{m["channel"]}"' in (root / 'Sources/BusymateAI/BusymateAI.swift').read_text()
assert f'sdkVersion = "{m["version"]}"' in (root / 'Sources/BusymateAI/BusymateAI.swift').read_text()
assert 'static let build = "2.0.0"' in (root / 'Sources/BusymateAI/BusymateBridge.swift').read_text()
assert (root / 'CONTRACT-v2.md').exists()

# Build success on a newer Xcode alone cannot detect an incompatible saved project format.
project = (root / 'example-app/BusymateSDKExample.xcodeproj/project.pbxproj').read_text()
version = re.search(r'objectVersion = (\d+);', project)
assert version and int(version.group(1)) == 60, 'Expected Xcode 15 project format (objectVersion 60)'
assert 'projectFormat: xcode15_0' in (root / 'example-app/project.yml').read_text()
assert 'PBXFileSystemSynchronizedRootGroup' not in project
print('verified example Xcode 15 project format (objectVersion 60)')

# The example declares what a sandboxed macOS chat host needs: network, microphone and its usage string.
ent = plistlib.loads((root / 'example-app/BusymateSDKExample.entitlements').read_bytes())
for key in ('com.apple.security.app-sandbox', 'com.apple.security.network.client', 'com.apple.security.device.audio-input'):
    assert ent.get(key) is True, f'missing entitlement {key}'
info = plistlib.loads((root / 'example-app/Info.plist').read_bytes())
assert info.get('NSMicrophoneUsageDescription'), 'missing NSMicrophoneUsageDescription'
print('verified example entitlements and NSMicrophoneUsageDescription')
