"""Generate non-secret source identity before XcodeGen builds."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, re, subprocess

ROOT = Path(__file__).resolve().parents[1]
config = (ROOT / 'ios/project.yml').read_text(encoding='utf-8')
contract_path = ROOT / 'ios/WhaleAgent/Resources/tools.v1.json'
contract = json.loads(contract_path.read_text(encoding='utf-8-sig'))
identity = {
    'gitSHA': os.environ.get('GITHUB_SHA') or subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
    'builtAt': datetime.now(timezone.utc).isoformat(),
    'version': re.search(r'MARKETING_VERSION:\s*"([^"]+)"', config).group(1),
    'sourceBuild': re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', config).group(1),
    'toolCount': len(contract['tools']),
    'directToolCount': sum(t['name'] != 'summarize_shared_content' for t in contract['tools']),
    'toolSHA256': hashlib.sha256(contract_path.read_bytes()).hexdigest(),
    'distribution': os.environ.get('WHALE_DISTRIBUTION', 'personal'),
    'runId': os.environ.get('GITHUB_RUN_ID', 'local'),
}
path = ROOT / 'ios/WhaleAgent/Resources/build-identity.json'
path.write_text(json.dumps(identity, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(identity, ensure_ascii=False))
