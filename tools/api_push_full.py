#!/usr/bin/env python3
# GitHub Data API 全量树推送（空仓库 → 单孤儿提交 → main）
import base64, json, subprocess, sys, urllib.request

TOK = open('/tmp/.ghtok').read().strip()
OWNER, REPO = 'yoyo520956', 'feather-cn'
API = f'https://api.github.com/repos/{OWNER}/{REPO}'

def api(method, path, payload=None, raw=False):
    last = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(f'{API}/{path}', method=method)
            req.add_header('Authorization', f'token {TOK}')
            req.add_header('Accept', 'application/vnd.github+json')
            data = None
            if payload is not None:
                data = json.dumps(payload).encode()
                req.add_header('Content-Type', 'application/json')
            with urllib.request.urlopen(req, data=data, timeout=120) as r:
                body = r.read()
                return json.loads(body) if body and not raw else (r.status, body)
        except urllib.error.HTTPError as e:
            print('HTTP', e.code, e.read()[:300].decode(errors='replace'))
            raise
        except Exception as e:  # DNS/SSL 抖动 → 重试
            last = e
            import time
            time.sleep(2 + attempt * 3)
            print(f'  网络重试 {attempt+1}: {e}')
    raise last

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()

# 1. 收集全部 git 条目（含 gitlink）
entries = []
for line in sh('git ls-files -s').split('\n'):
    if not line.strip():
        continue
    mode, sha, _, path = line.split(None, 3)
    entries.append((mode, sha, path))
print(f'本地条目 {len(entries)} 个')

# 2. 建 tree 节点（gitlink 直接带 sha；blob 需上传，带断点缓存）
CACHE = '/tmp/feather_blob_cache.json'
try:
    cache = json.load(open(CACHE))
except Exception:
    cache = {}

tree = []
created = 0
for mode, sha, path in entries:
    if mode == '160000':
        tree.append({'path': path, 'mode': '160000', 'type': 'commit', 'sha': sha})
        continue
    if sha in cache:  # 断点续传：跳过已上传
        tree.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': cache[sha]})
        continue
    content = open(path, 'rb').read()
    blob = api('POST', 'git/blobs', {
        'content': base64.b64encode(content).decode(),
        'encoding': 'base64',
    })
    cache[sha] = blob['sha']
    json.dump(cache, open(CACHE, 'w'))
    tree.append({'path': path, 'mode': mode, 'type': 'blob', 'sha': blob['sha']})
    created += 1
    if created % 40 == 0:
        print(f'  已上传 blob {created}')
print(f'本轮新建 blob {created}，缓存命中 {len(cache)}')

# 3. 建树（挂到 README 首提交之下，保留历史）
head_now = api('GET', 'commits/main')
parent_sha = head_now['sha']
print('当前远端 HEAD:', parent_sha[:7])

new_tree = api('POST', 'git/trees', {'tree': tree})
print('树 sha:', new_tree['sha'])

# 4. 提交 + 引用
commit = api('POST', 'git/commits', {
    'message': sh('git log -1 --pretty=%B'),
    'tree': new_tree['sha'],
    'parents': [parent_sha],
})
print('提交 sha:', commit['sha'])

api('PATCH', 'git/refs/heads/main', {'sha': commit['sha']})
print('refs/heads/main 已更新')

# 5. 校验
head = api('GET', 'commits/main')
print('远端 HEAD:', head['sha'][:7], head['commit']['message'].split('\n')[0][:60])
print('VERIFY', 'OK' if head['sha'] == commit['sha'] else 'MISMATCH')
