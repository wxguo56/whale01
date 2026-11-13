"""Verify identity and distribution boundaries without logging secret values."""
from pathlib import Path
import argparse, hashlib, json, plistlib, zipfile

parser = argparse.ArgumentParser()
parser.add_argument('ipa', type=Path)
parser.add_argument('--sha', required=True)
parser.add_argument('--public', action='store_true')
args = parser.parse_args()
with zipfile.ZipFile(args.ipa) as archive:
    roots = [n for n in archive.namelist() if n.count('/') == 2 and n.startswith('Payload/') and n.endswith('.app/Info.plist')]
    if len(roots) != 1: raise SystemExit('Expected one application bundle')
    app = roots[0].rsplit('/', 1)[0]
    info = plistlib.loads(archive.read(roots[0]))
    identity = json.loads(archive.read(app + '/build-identity.json'))
    tools = archive.read(app + '/tools.v1.json')
    present = lambda value: isinstance(value, str) and bool(value.strip()) and not value.startswith('$(')
    embedded = any(present(info.get(k)) for k in ['DeepSeekAPIKey', 'WhaleAPIToken', 'XfyunAPIKey', 'XfyunAPISecret'])
    assert identity['gitSHA'] == args.sha, 'IPA source SHA mismatch'
    assert info['CFBundleShortVersionString'] == identity['version'], 'IPA version mismatch'
    assert hashlib.sha256(tools).hexdigest() == identity['toolSHA256'], 'Tool manifest mismatch'
    assert len(json.loads(tools)['tools']) == identity['toolCount'], 'Tool count mismatch'
    if (args.public or identity['distribution'] == 'public') and embedded:
        raise SystemExit('Public distribution blocked: embedded long-lived credential detected')
    result = {**identity, 'bundleId': info['CFBundleIdentifier'], 'installedBuild': info['CFBundleVersion'],
              'ipaSHA256': hashlib.sha256(args.ipa.read_bytes()).hexdigest(), 'bytes': args.ipa.stat().st_size,
              'embeddedCredentialPresent': embedded, 'publicDistributionAllowed': not embedded}
    output = args.ipa.with_suffix('.manifest.json')
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
