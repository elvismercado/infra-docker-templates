import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.join(testDirectory, '..');
const readProjectFile = (name) => fs.readFileSync(path.join(projectDirectory, name), 'utf8');

const composeFile = readProjectFile('docker-compose.yml');
assert.match(composeFile, /ghcr\.io\/community-valheim-tools\/valheim-server/);
assert.match(composeFile, /\$\{APP_DATA_PATH:-\/tmp\/valheim\}\/valheim-server\/config:\/config/);
assert.match(composeFile, /\$\{APP_DATA_PATH:-\/tmp\/valheim\}\/valheim-server\/data:\/opt\/valheim/);
assert.match(composeFile, /stop_grace_period: 2m/);
assert.match(composeFile, /supervisorctl status valheim-server \| grep -q RUNNING/);
assert.doesNotMatch(composeFile, /:9001\/tcp/);
assert.doesNotMatch(composeFile, /:80\/tcp/);

const statusOverlay = readProjectFile('docker-compose.status.yml');
assert.match(statusOverlay, /\$\{STATUS_PORT:-2454\}:80\/tcp/);

const supervisorOverlay = readProjectFile('docker-compose.supervisor.yml');
assert.match(supervisorOverlay, /\$\{SUPERVISOR_PORT:-2455\}:9001\/tcp/);

const serverEnvironment = readProjectFile('valheim.env.example');
assert.match(serverEnvironment, /^VALHEIM_PLUS=false$/m);
assert.match(serverEnvironment, /^BEPINEX=false$/m);
assert.match(serverEnvironment, /^CROSSPLAY=false$/m);
assert.match(serverEnvironment, /^SUPERVISOR_HTTP=false$/m);
assert.match(serverEnvironment, /^STATUS_HTTP=false$/m);

console.log('Valheim template regression tests passed.');