import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const composeFile = fs.readFileSync(path.join(testDirectory, '..', 'docker-compose.yml'), 'utf8');
assert.match(composeFile, /VR_PRESET: \$\{GAME_SETTINGS_PRESET-StandardPvE\}/);

const composePreset = (environment) => (
  Object.hasOwn(environment, 'GAME_SETTINGS_PRESET')
    ? environment.GAME_SETTINGS_PRESET
    : 'StandardPvE'
);
assert.equal(composePreset({}), 'StandardPvE');
assert.equal(composePreset({ GAME_SETTINGS_PRESET: '' }), '');
assert.equal(composePreset({ GAME_SETTINGS_PRESET: 'StandardPvE' }), 'StandardPvE');

const currentSettings = {
  GameModeType: 'PvE',
  CastleDamageMode: 'Never',
  ClanSize: 4,
  InventoryStacksModifier: 1.5,
  nested: {
    preserve: true,
  },
};

const mergeClanSize = (settings, clanSize) => ({
  ...settings,
  ClanSize: Number.parseInt(clanSize, 10),
});

const mergeTravelSettings = (settings, options) => ({
  ...settings,
  ...(options.teleport_with_items === undefined
    ? {}
    : { TeleportBoundItems: !options.teleport_with_items }),
  ...(options.bat_form_with_items === undefined
    ? {}
    : { BatBoundItems: !options.bat_form_with_items }),
  ...(options.bat_form_with_soul_shards === undefined
    ? {}
    : { BatBoundShards: !options.bat_form_with_soul_shards }),
});

const desiredSettings = mergeClanSize(currentSettings, '20');
assert.equal(desiredSettings.ClanSize, 20);
assert.equal(typeof desiredSettings.ClanSize, 'number');
assert.equal(desiredSettings.GameModeType, currentSettings.GameModeType);
assert.equal(desiredSettings.CastleDamageMode, currentSettings.CastleDamageMode);
assert.equal(desiredSettings.InventoryStacksModifier, currentSettings.InventoryStacksModifier);
assert.deepEqual(desiredSettings.nested, currentSettings.nested);

const travelSettings = mergeTravelSettings(currentSettings, {
  teleport_with_items: true,
  bat_form_with_items: true,
  bat_form_with_soul_shards: true,
});
assert.equal(travelSettings.TeleportBoundItems, false);
assert.equal(travelSettings.BatBoundItems, false);
assert.equal(travelSettings.BatBoundShards, false);
assert.equal(travelSettings.ClanSize, currentSettings.ClanSize);
assert.deepEqual(travelSettings.nested, currentSettings.nested);

const mixedTravelSettings = mergeTravelSettings(currentSettings, {
  teleport_with_items: false,
  bat_form_with_items: false,
  bat_form_with_soul_shards: false,
});
assert.equal(mixedTravelSettings.TeleportBoundItems, true);
assert.equal(mixedTravelSettings.BatBoundItems, true);
assert.equal(mixedTravelSettings.BatBoundShards, true);

const partialTravelSettings = mergeTravelSettings(currentSettings, {
  teleport_with_items: true,
});
assert.equal(partialTravelSettings.TeleportBoundItems, false);
assert.equal(partialTravelSettings.BatBoundItems, undefined);
assert.equal(partialTravelSettings.BatBoundShards, undefined);

const unchangedTravelSettings = mergeTravelSettings(currentSettings, {});
assert.deepEqual(unchangedTravelSettings, currentSettings);

for (const clanSize of [1, 4, 20, 50]) {
  assert.ok(clanSize >= 1 && clanSize <= 50);
}

for (const clanSize of [0, 51]) {
  assert.ok(!(clanSize >= 1 && clanSize <= 50));
}

console.log('V Rising settings regression tests passed.');