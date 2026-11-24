import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const deploy = readFileSync('.github/workflows/deploy-web-production.yml', 'utf8');
const android = readFileSync('.github/workflows/cliente-android-aab.yml', 'utf8');

test('fusionar un PR en main activa la publicación automática', () => {
  assert.match(deploy, /^on:\\r?\\n  push:\\r?\\n    branches: \\[main\\]/m);
  assert.match(deploy, /github\\.ref == 'refs\\/heads\\/main'/);
  assert.match(deploy, /github\\.event_name == 'push'/);
  assert.match(deploy, /Verify automatic main update comes from a merged PR/);
  assert.match(deploy, /github\\.event_name == 'push' }}\\n        shell: bash/);
  assert.match(deploy, /gh api "repos\\/\\$\\{GITHUB_REPOSITORY\\}\\/commits\\/\\$\\{GITHUB_SHA\\}\\/pulls"/);
  assert.match(deploy, /pr\\.merged_at/);
  assert.match(deploy, /pr\\.base\\?\\.ref === 'main'/);
  assert.match(deploy, /pr\\.merge_commit_sha === process\\.env\\.GITHUB_SHA/);
  assert.match(deploy, /AUTO_DEPLOY_REJECTED/);
  assert.match(deploy, /^  contents: read$/m);
  assert.match(deploy, /^  pull-requests: read$/m);
});

test('se conserva publicación manual solo con confirmación expresa', () => {
  assert.match(deploy, /^  workflow_dispatch:$/m);
  assert.match(deploy, /confirm_production:/);
  assert.match(deploy, /github\\.event_name == 'workflow_dispatch' && inputs\\.confirm_production == true/);
  assert.match(deploy, /github\\.ref == 'refs\\/heads\\/main'/);
});

test('no se publica codigo superado y se comprueba el artefacto web', () => {
  const beforeUpload = deploy.indexOf('- name: Reject stale main commit before upload');
  const upload = deploy.indexOf('- name: Upload exact build to existing Worker');
  const beforeActivation = deploy.indexOf('- name: Reject stale main commit before activation');
  const activate = deploy.indexOf('- name: Promote uploaded version to 100 percent');
  assert.ok(beforeUpload >= 0 && beforeUpload < upload);
  assert.ok(beforeActivation >= 0 && beforeActivation < activate);
  assert.match(deploy, /PRODUCTION_INTEGRITY=OK/);
  assert.match(deploy, /flutter test/);
  assert.match(deploy, /CLOUDFLARE_API_TOKEN/);
  assert.doesNotMatch(deploy, /flutter build (?:apk|appbundle)/);
});

test('Android no se inicia con cambios en main', () => {
  assert.match(android, /^  workflow_dispatch:$/m);
  assert.doesNotMatch(android, /^  push:$/m);
  assert.doesNotMatch(android, /^  pull_request:$/m);
});
