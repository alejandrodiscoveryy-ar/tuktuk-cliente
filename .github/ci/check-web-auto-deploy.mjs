import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const deploy = readFileSync('.github/workflows/deploy-web-production.yml', 'utf8');
const android = readFileSync('.github/workflows/cliente-android-aab.yml', 'utf8');

test('fusionar un PR en main activa la publicación automática', () => {
  assert.ok(deploy.includes('on:\n  push:\n    branches: [main]'));
  assert.ok(deploy.includes("github.ref == 'refs/heads/main'"));
  assert.ok(deploy.includes("github.event_name == 'push'"));
  assert.ok(deploy.includes('Verify automatic main update comes from a merged PR'));
  assert.ok(deploy.includes('gh api "repos/${GITHUB_REPOSITORY}/commits/${GITHUB_SHA}/pulls"'));
  assert.ok(deploy.includes("pr.merged_at"));
  assert.ok(deploy.includes("pr.base?.ref === 'main'"));
  assert.ok(deploy.includes("pr.merge_commit_sha === process.env.GITHUB_SHA"));
  assert.ok(deploy.includes('AUTO_DEPLOY_REJECTED'));
  assert.match(deploy, /^  contents: read$/m);
  assert.match(deploy, /^  pull-requests: read$/m);
});

test('se conserva publicación manual solo con confirmación expresa', () => {
  assert.match(deploy, /^  workflow_dispatch:$/m);
  assert.ok(deploy.includes('confirm_production:'));
  assert.ok(deploy.includes("github.event_name == 'workflow_dispatch' && inputs.confirm_production == true"));
  assert.ok(deploy.includes("github.ref == 'refs/heads/main'"));
});

test('no se publica código superado y se comprueba el artefacto web', () => {
  const beforeUpload = deploy.indexOf('- name: Reject stale main commit before upload');
  const upload = deploy.indexOf('- name: Upload exact build to existing Worker');
  const beforeActivation = deploy.indexOf('- name: Reject stale main commit before activation');
  const activate = deploy.indexOf('- name: Promote uploaded version to 100 percent');
  assert.ok(beforeUpload >= 0 && beforeUpload < upload);
  assert.ok(beforeActivation >= 0 && beforeActivation < activate);
  assert.ok(deploy.includes('Verify approved commit is still main HEAD'));
  assert.ok(deploy.includes('PRODUCTION_INTEGRITY=OK'));
  assert.ok(deploy.includes('flutter test'));
  assert.ok(deploy.includes('CLOUDFLARE_API_TOKEN'));
  assert.doesNotMatch(deploy, /flutter build (?:apk|appbundle)/);
});

test('Android no se inicia con cambios en main', () => {
  assert.match(android, /^  workflow_dispatch:$/m);
  assert.doesNotMatch(android, /^  push:$/m);
  assert.doesNotMatch(android, /^  pull_request:$/m);
});
