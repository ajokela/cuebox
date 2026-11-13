#!/usr/bin/env python3
"""Upload built public artifacts to this website's CloudFormation-owned bucket.

No credentials, account IDs or deployment state are stored in the source tree.
Requires AWS CLI credentials authorized for the named stack and its resources.
"""
import argparse
import json
import mimetypes
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--stack', default='cuebox-website')
parser.add_argument('--region', default='us-east-1')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
dist = root / 'build/website/dist'
for required in ('index.html', 'assets/social.png', 'play/index.wasm.gz', 'play/index.pck.gz', 'licenses/index.html'):
    if not (dist / required).is_file(): raise SystemExit(f'Build is incomplete: {required}')

def aws(*command):
    return json.loads(subprocess.check_output(['aws', *command, '--region', args.region, '--output', 'json']))

stack = aws('cloudformation', 'describe-stacks', '--stack-name', args.stack)['Stacks'][0]
if stack['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE'):
    raise SystemExit(f"Stack not ready: {stack['StackStatus']}")
outputs = {x['OutputKey']:x['OutputValue'] for x in stack['Outputs']}
bucket, distribution = outputs['BucketName'], outputs['DistributionId']
types = {'.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8', '.svg':'image/svg+xml', '.ttf':'font/ttf', '.wasm':'application/wasm', '.pck':'application/octet-stream', '.txt':'text/plain; charset=utf-8', '.xml':'application/xml'}
manifest = []
for source in sorted(dist.rglob('*')):
    if not source.is_file() or source.suffix == '.gz': continue
    key = source.relative_to(dist).as_posix()
    # dist is an allowlisted output directory, never a source/repository upload.
    content_type = types.get(source.suffix, mimetypes.guess_type(key)[0] or 'application/octet-stream')
    cache = 'no-cache' if source.suffix == '.html' else 'public, max-age=3600'
    compressed = source.with_suffix(source.suffix + '.gz')
    extra = ['--content-encoding', 'gzip'] if compressed.is_file() else []
    payload = compressed if compressed.is_file() else source
    result = aws('s3api', 'put-object', '--bucket', bucket, '--key', key, '--body', str(payload), '--content-type', content_type, '--cache-control', cache, *extra)
    manifest.append({'key':key, 'bytes':payload.stat().st_size, 'etag':result['ETag']})
    print(f'Uploaded {key}')
invalidation = aws('cloudfront', 'create-invalidation', '--distribution-id', distribution, '--paths', '/*')
report = {'stack':args.stack, 'outputs':outputs, 'files':manifest, 'invalidation':invalidation['Invalidation']['Id']}
(root / 'build/website/deployment.json').write_text(json.dumps(report, indent=2)+'\n')
print(f"Uploaded {len(manifest)} public files. Invalidation: {report['invalidation']}")
