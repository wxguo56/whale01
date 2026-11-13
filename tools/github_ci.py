"""Inspect this repository's Actions without printing credentials or raw logs."""
import argparse, io, json, os, re, subprocess, urllib.request, urllib.error, zipfile, time
parser = argparse.ArgumentParser()
parser.add_argument('--branch', default='codex/whale-reliability')
parser.add_argument('--run', type=int)
parser.add_argument('--dispatch')
parser.add_argument('--scope')
parser.add_argument('--log-pattern')
parser.add_argument('--logs', action='store_true')
parser.add_argument('--download-artifact', type=int)
parser.add_argument('--out')
parser.add_argument('--artifacts', action='store_true')
parser.add_argument('--create-draft-pr', action='store_true')
parser.add_argument('--title')
parser.add_argument('--body-file')
args = parser.parse_args()
env = {**os.environ, 'GIT_TERMINAL_PROMPT': '0'}
credential = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n', text=True, capture_output=True, env=env, timeout=30)
fields = dict(line.split('=', 1) for line in credential.stdout.splitlines() if '=' in line)
token = fields.get('password', '')
if not token: raise SystemExit('GitHub credential helper did not provide an existing credential')
base = 'https://api.github.com/repos/wxguo56/whale01'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl): return None
def download(path):
    # GitHub returns a short-lived signed storage URL. Never forward the
    # GitHub Authorization header to that different origin.
    req = urllib.request.Request(base + path + '?nocache=' + str(time.time_ns()),
        headers={'Authorization': 'Bearer ' + token, 'User-Agent': 'WhaleReliabilityReview', 'Cache-Control': 'no-cache'})
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=30) as response: return response.read()
    except urllib.error.HTTPError as error:
        if error.code != 302: raise
        url = error.headers['Location']
        if not url.startswith('https://'): raise RuntimeError('Unsafe download redirect')
        with urllib.request.urlopen(urllib.request.Request(url, headers={'Cache-Control':'no-cache'}), timeout=30) as response: return response.read()
def request(path, method='GET', body=None):
    req = urllib.request.Request(base + path, method=method,
        headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json', 'User-Agent': 'WhaleReliabilityReview'},
        data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req, timeout=30) as result:
        data = result.read()
    return json.loads(data) if data else None
if args.create_draft_pr:
    from pathlib import Path
    from urllib.parse import quote
    if not args.title or not args.body_file: raise SystemExit('--title and --body-file are required')
    existing = request('/pulls?state=open&base=main&head=' + quote('wxguo56:' + args.branch, safe=''))
    pr = request('/pulls/' + str(existing[0]['number']), 'PATCH', {
        'title': args.title, 'body': Path(args.body_file).read_text(encoding='utf-8')
    }) if existing else request('/pulls', 'POST', {
        'title': args.title, 'head': args.branch, 'base': 'main', 'draft': True,
        'body': Path(args.body_file).read_text(encoding='utf-8')
    })
    print(json.dumps({k:pr.get(k) for k in ['number','html_url','draft','state']}, ensure_ascii=False))
elif args.download_artifact:
    from pathlib import Path
    if not args.out: raise SystemExit('--out is required')
    Path(args.out).write_bytes(download('/actions/artifacts/' + str(args.download_artifact) + '/zip'))
    print('Downloaded artifact to ' + args.out)
elif args.dispatch:
    request('/actions/workflows/' + args.dispatch + '/dispatches', 'POST', {'ref': args.branch, **({'inputs': {'scope': args.scope}} if args.scope else {})})
    print('Dispatched ' + args.dispatch + ' for ' + args.branch)
elif args.run:
    run = request('/actions/runs/' + str(args.run))
    if args.artifacts:
        items = request('/actions/runs/' + str(args.run) + '/artifacts')['artifacts']
        print(json.dumps([{k:item.get(k) for k in ['id','name','size_in_bytes','expired']} for item in items], ensure_ascii=False))
        raise SystemExit(0)
    jobs = request('/actions/runs/' + str(args.run) + '/jobs')
    print(json.dumps({k: run.get(k) for k in ['id','name','status','conclusion','head_sha','html_url','created_at','updated_at']}, ensure_ascii=False))
    for job in jobs['jobs']:
        print(json.dumps({'job':job['name'],'status':job['status'],'conclusion':job['conclusion'], 'steps':[{k:step.get(k) for k in ['name','status','conclusion','started_at','completed_at']} for step in job['steps']]}, ensure_ascii=False))
        if job['conclusion'] == 'failure' or args.logs:
            try: log = download('/actions/jobs/' + str(job['id']) + '/logs').decode('utf-8', errors='replace')
            except urllib.error.HTTPError as error:
                print('Logs unavailable: HTTP ' + str(error.code))
                continue
            if args.log_pattern:
                print('\n'.join(line for line in log.splitlines() if re.search(args.log_pattern, line))[-18000:])
                continue
            errors = [line for line in log.splitlines() if re.search(r'error:|Test Case .*failed|fatal error|XCTAssert|failed -|Executed [0-9]+ tests|Test Suite .*passed|Testing started|Test Case .*passed', line)]
            if job['conclusion'] == 'failure':
                failures = [line for line in log.splitlines() if re.search(r'error:|Test Case .*failed|fatal error|XCTAssert|failed -', line)]
                print('\n'.join(failures[-40:]))
            print('\n'.join(errors[-60:]))
else:
    from urllib.parse import quote
    data = request('/actions/runs?branch=' + quote(args.branch, safe='') + '&per_page=8')
    print(json.dumps([{k:run.get(k) for k in ['id','name','status','conclusion','head_sha','html_url']} for run in data['workflow_runs']], ensure_ascii=False, indent=2))
