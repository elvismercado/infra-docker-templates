import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const mediaDirectory = path.join(testDirectory, '..');
const readMediaFile = (name) => fs.readFileSync(path.join(mediaDirectory, name), 'utf8');

console.log('Running media docker template regression tests...');

// 1. Networks
const networks = readMediaFile('networks.yml');
assert.match(networks, /name: \$\{CONTAINER_NAME_PREFIX:-media\}-net/);

// 2. Main docker-compose.yml
const mainCompose = readMediaFile('docker-compose.yml');
assert.match(mainCompose, /name: \$\{CONTAINER_NAME_PREFIX:-media\}/);
assert.match(mainCompose, /file: players\/kavita\.yml/);
assert.match(mainCompose, /file: indexers\/autobrr\.yml/);
assert.match(mainCompose, /file: managers\/lidarr\.yml/);
assert.match(mainCompose, /file: managers\/readarr\.yml/);
assert.match(mainCompose, /file: dashboards\/homarr\.yml/);

// 3. Bazarr
const bazarr = readMediaFile('managers/bazarr.yml');
assert.match(bazarr, /container_name: \$\{CONTAINER_NAME_PREFIX:-media\}-bazarr-anime-hd/);
assert.match(bazarr, /hostname: \$\{CONTAINER_NAME_PREFIX:-media\}-bazarr-anime-hd/);

// 4. Modernized inactive templates
const modernizedTemplates = [
  'players/kavita.yml',
  'indexers/autobrr.yml',
  'managers/lidarr.yml',
  'managers/readarr.yml',
  'dashboards/homarr.yml'
];

for (const templatePath of modernizedTemplates) {
  const content = readMediaFile(templatePath);
  assert.doesNotMatch(content, /version:\s*['"]?3\.9['"]?/, `Obsolete version tag found in ${templatePath}`);
  assert.doesNotMatch(content, /APPDATA_BASE_PATH/, `Legacy APPDATA_BASE_PATH found in ${templatePath}`);
  assert.doesNotMatch(content, /-\s*media-net/, `Legacy media-net found in ${templatePath}`);
  assert.match(content, /networks:\s*\n\s*-\s*default/, `Missing default network in ${templatePath}`);
  assert.match(content, /com\.service=/, `Missing com.service label in ${templatePath}`);
}

// 5. GHCR Migrations (FlareSolverr, Gluetun, Recyclarr)
const flaresolverr = readMediaFile('indexers/flaresolverr.yml');
assert.match(flaresolverr, /image: ghcr\.io\/flaresolverr\/flaresolverr:\$\{FLARESOLVERR_VERSION:-latest\}/);

const gluetun = readMediaFile('vpns/gluetun.yml');
assert.match(gluetun, /image: ghcr\.io\/qdm12\/gluetun:\$\{GLUETUN_VERSION:-latest\}/);

const recyclarr = readMediaFile('managers/utilities/recyclarr.yml');
assert.match(recyclarr, /image: ghcr\.io\/recyclarr\/recyclarr:\$\{RECYCLARR_VERSION:-7\}/);

// 6. Environment example
const envExample = readMediaFile('.env.example');
assert.match(envExample, /^NZBGET_HTTP_PORT=6789$/m);
assert.match(envExample, /^TRANSMISSION_WEB_HOME=$/m);
assert.match(envExample, /^RECYCLARR_VERSION=7$/m);
assert.match(envExample, /^AUTOBRR_VERSION=latest$/m);
assert.match(envExample, /^HOMARR_VERSION=latest$/m);
assert.doesNotMatch(envExample, /HOMARR_VERSSION/);

console.log('✓ All media docker template regression tests passed successfully!');
