import hashlib, json, plistlib, zipfile
from pathlib import Path

root = Path(r'F:\VS_t\代号鲸鱼01')
ipa = root / 'release/WhaleAgent-Sideload.ipa'
with zipfile.ZipFile(ipa) as z:
    plist_name = next(n for n in z.namelist() if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2)
    app_root = plist_name.rsplit('/', 1)[0]
    p = plistlib.loads(z.read(plist_name))
    tool_name = next(n for n in z.namelist() if n.startswith(app_root + '/') and n.endswith('/tools.v1.json'))
    package_tools = json.loads(z.read(tool_name))['tools']
    def configured(v):
        return isinstance(v, str) and bool(v.strip()) and not v.strip().startswith('$(')
    result = {
        'version': p.get('CFBundleShortVersionString'), 'build': p.get('CFBundleVersion'),
        'bundleID': p.get('CFBundleIdentifier'), 'bytes': ipa.stat().st_size,
        'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'toolManifestCount': len(package_tools),
        'directCallableCount': sum(t['name'] != 'summarize_shared_content' for t in package_tools),
        'toolNames': [t['name'] for t in package_tools],
        'deepseekConfigured': configured(p.get('DeepSeekAPIKey')),
        'xfyunConfigFlags': {k: configured(p.get(k)) for k in ['XFYUN_APP_ID', 'XFYUN_API_KEY', 'XFYUN_API_SECRET']},
        'extensions': [n.split('/')[-2] for n in z.namelist() if n.endswith('.appex/Info.plist')],
        'backgroundModes': p.get('UIBackgroundModes', []),
    }
for label, path in [('contract', 'contracts/v1/tools.v1.json'), ('native', 'ios/WhaleAgent/Resources/tools.v1.json')]:
    tools = json.loads((root/path).read_text(encoding='utf-8'))['tools']
    result[label+'Count'] = len(tools)
    result[label+'NamesEqualPackage'] = [t['name'] for t in tools] == result['toolNames']
out = root/'review/functional-audit-2026-11-10/package-facts.json'
out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
