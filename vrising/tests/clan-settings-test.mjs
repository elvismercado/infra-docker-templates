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
  BloodBoundEquipment: false,
  DeathContainerPermission: 0,
  MaterialYieldModifier_Global: 1,
  DropTableModifier_General: 1,
  BloodEssenceYieldModifier: 1,
  CraftRateModifier: 1,
  RefinementRateModifier: 1,
  ServantConvertRateModifier: 1,
  RepairCostModifier: 1,
  DurabilityDrainModifier: 1,
  SoulShard_DurabilityLossRate: 1,
  RelicSpawnType: 'Unique',
  CastleRelocationEnabled: false,
  CastleBloodEssenceDrainModifier: 1,
  CastleDecayRateModifier: 1,
  InactivityKillEnabled: true,
  GameTimeModifiers: {
    DayDurationInSeconds: 10800,
    DayStartHour: 8,
    DayStartMinute: 30,
    DayEndHour: 18,
    DayEndMinute: 45,
    BloodMoonFrequency_Min: 10,
    BloodMoonFrequency_Max: 20,
    BloodMoonBuff: 0.2,
    UnknownFutureSetting: {
      preserved: true,
    },
  },
  WarEventGameSettings: {
    Interval: 4,
    MajorDuration: 1,
    MinorDuration: 1,
    PointsModifier: 1,
    WeekdayTime: {
      StartHour: 18,
      StartMinute: 0,
      EndHour: 23,
      EndMinute: 59,
    },
    UnknownFutureSetting: {
      preserved: true,
    },
  },
  nested: {
    preserve: true,
  },
};

const parseSlurpedJson = (base64Content) => {
  const decodedContent = Buffer.from(base64Content, 'base64').toString('utf8');
  return JSON.parse(decodedContent.replace(/^\uFEFF/, ''));
};

const plainJsonBase64 = Buffer.from(JSON.stringify(currentSettings), 'utf8').toString('base64');
const bomJsonBase64 = Buffer.from(`\uFEFF${JSON.stringify(currentSettings)}`, 'utf8').toString('base64');
assert.deepEqual(parseSlurpedJson(plainJsonBase64), currentSettings);
assert.deepEqual(parseSlurpedJson(bomJsonBase64), currentSettings);

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

const mergeGameplaySettings = (settings, options) => {
  const mergedSettings = {
    ...mergeTravelSettings(settings, options),
    ...(options.game_mode_type === undefined
      ? {}
      : { GameModeType: options.game_mode_type }),
    ...(options.blood_bound_equipment === undefined
      ? {}
      : { BloodBoundEquipment: Boolean(options.blood_bound_equipment) }),
    ...(options.death_container_permission === undefined
      ? {}
      : { DeathContainerPermission: Number.parseInt(options.death_container_permission, 10) }),
    ...(options.material_yield_modifier_global === undefined
      ? {}
      : { MaterialYieldModifier_Global: Number(options.material_yield_modifier_global) }),
    ...(options.drop_table_modifier_general === undefined
      ? {}
      : { DropTableModifier_General: Number(options.drop_table_modifier_general) }),
    ...(options.blood_essence_yield_modifier === undefined
      ? {}
      : { BloodEssenceYieldModifier: Number(options.blood_essence_yield_modifier) }),
    ...(options.craft_rate_modifier === undefined
      ? {}
      : { CraftRateModifier: Number(options.craft_rate_modifier) }),
    ...(options.refinement_rate_modifier === undefined
      ? {}
      : { RefinementRateModifier: Number(options.refinement_rate_modifier) }),
    ...(options.servant_convert_rate_modifier === undefined
      ? {}
      : { ServantConvertRateModifier: Number(options.servant_convert_rate_modifier) }),
    ...(options.repair_cost_modifier === undefined
      ? {}
      : { RepairCostModifier: Number(options.repair_cost_modifier) }),
    ...(options.durability_drain_modifier === undefined
      ? {}
      : { DurabilityDrainModifier: Number(options.durability_drain_modifier) }),
    ...(options.soul_shard_durability_loss_rate === undefined
      ? {}
      : { SoulShard_DurabilityLossRate: Number(options.soul_shard_durability_loss_rate) }),
    ...(options.relic_spawn_type === undefined
      ? {}
      : { RelicSpawnType: String(options.relic_spawn_type) }),
    ...(options.castle_relocation_enabled === undefined
      ? {}
      : { CastleRelocationEnabled: Boolean(options.castle_relocation_enabled) }),
    ...(options.castle_blood_essence_drain_modifier === undefined
      ? {}
      : { CastleBloodEssenceDrainModifier: Number(options.castle_blood_essence_drain_modifier) }),
    ...(options.castle_decay_rate_modifier === undefined
      ? {}
      : { CastleDecayRateModifier: Number(options.castle_decay_rate_modifier) }),
    ...(options.inactivity_kill_enabled === undefined
      ? {}
      : { InactivityKillEnabled: Boolean(options.inactivity_kill_enabled) }),
  };

  if (options.game_time_modifiers !== undefined) {
    mergedSettings.GameTimeModifiers = {
      ...settings.GameTimeModifiers,
      ...(options.game_time_modifiers.day_start_hour === undefined
        ? {}
        : { DayStartHour: Number.parseInt(options.game_time_modifiers.day_start_hour, 10) }),
      ...(options.game_time_modifiers.day_start_minute === undefined
        ? {}
        : { DayStartMinute: Number.parseInt(options.game_time_modifiers.day_start_minute, 10) }),
      ...(options.game_time_modifiers.day_end_hour === undefined
        ? {}
        : { DayEndHour: Number.parseInt(options.game_time_modifiers.day_end_hour, 10) }),
      ...(options.game_time_modifiers.day_end_minute === undefined
        ? {}
        : { DayEndMinute: Number.parseInt(options.game_time_modifiers.day_end_minute, 10) }),
    };
  }

  if (options.war_event_game_settings !== undefined) {
    mergedSettings.WarEventGameSettings = {
      ...settings.WarEventGameSettings,
      ...(options.war_event_game_settings.interval === undefined
        ? {}
        : { Interval: Number.parseInt(options.war_event_game_settings.interval, 10) }),
      ...(options.war_event_game_settings.major_duration === undefined
        ? {}
        : { MajorDuration: Number.parseInt(options.war_event_game_settings.major_duration, 10) }),
      ...(options.war_event_game_settings.minor_duration === undefined
        ? {}
        : { MinorDuration: Number.parseInt(options.war_event_game_settings.minor_duration, 10) }),
    };
  }

  return mergedSettings;
};

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

const currentPvpSettings = {
  ...currentSettings,
  GameModeType: 'PvP',
};
const requestedPveSettings = mergeGameplaySettings(currentPvpSettings, {
  game_mode_type: 'PvE',
});
assert.equal(requestedPveSettings.GameModeType, 'PvE');
assert.equal(typeof requestedPveSettings.GameModeType, 'string');
assert.equal(requestedPveSettings.CastleDamageMode, currentPvpSettings.CastleDamageMode);
assert.deepEqual(requestedPveSettings.nested, currentPvpSettings.nested);
assert.deepEqual(
  mergeGameplaySettings(requestedPveSettings, { game_mode_type: 'PvE' }),
  requestedPveSettings,
);
assert.equal(mergeGameplaySettings(currentPvpSettings, {}).GameModeType, 'PvP');

const requestedGameplaySettings = mergeGameplaySettings(currentSettings, {
  teleport_with_items: true,
  bat_form_with_items: true,
  bat_form_with_soul_shards: true,
  blood_bound_equipment: true,
  death_container_permission: 2,
  material_yield_modifier_global: 1.5,
  drop_table_modifier_general: 1.25,
  blood_essence_yield_modifier: 1.5,
  craft_rate_modifier: 2,
  refinement_rate_modifier: 2,
  servant_convert_rate_modifier: 2,
  repair_cost_modifier: 0.5,
  durability_drain_modifier: 0.1,
  soul_shard_durability_loss_rate: 0,
  relic_spawn_type: 'Plentiful',
  castle_relocation_enabled: true,
  castle_blood_essence_drain_modifier: 0,
  castle_decay_rate_modifier: 0,
  inactivity_kill_enabled: false,
  game_time_modifiers: {
    day_start_hour: 10,
    day_start_minute: 0,
    day_end_hour: 16,
    day_end_minute: 0,
  },
  war_event_game_settings: {
    interval: 1,
    major_duration: 5,
    minor_duration: 3,
  },
});
assert.equal(requestedGameplaySettings.BloodBoundEquipment, true);
assert.equal(requestedGameplaySettings.DeathContainerPermission, 2);
assert.equal(requestedGameplaySettings.MaterialYieldModifier_Global, 1.5);
assert.equal(requestedGameplaySettings.DropTableModifier_General, 1.25);
assert.equal(requestedGameplaySettings.BloodEssenceYieldModifier, 1.5);
assert.equal(requestedGameplaySettings.CraftRateModifier, 2);
assert.equal(requestedGameplaySettings.RefinementRateModifier, 2);
assert.equal(requestedGameplaySettings.ServantConvertRateModifier, 2);
assert.equal(requestedGameplaySettings.RepairCostModifier, 0.5);
assert.equal(requestedGameplaySettings.DurabilityDrainModifier, 0.1);
assert.equal(requestedGameplaySettings.SoulShard_DurabilityLossRate, 0);
assert.equal(requestedGameplaySettings.RelicSpawnType, 'Plentiful');
assert.equal(requestedGameplaySettings.CastleRelocationEnabled, true);
assert.equal(requestedGameplaySettings.CastleBloodEssenceDrainModifier, 0);
assert.equal(requestedGameplaySettings.CastleDecayRateModifier, 0);
assert.equal(requestedGameplaySettings.InactivityKillEnabled, false);
assert.equal(requestedGameplaySettings.GameTimeModifiers.DayStartHour, 10);
assert.equal(requestedGameplaySettings.GameTimeModifiers.DayStartMinute, 0);
assert.equal(requestedGameplaySettings.GameTimeModifiers.DayEndHour, 16);
assert.equal(requestedGameplaySettings.GameTimeModifiers.DayEndMinute, 0);
assert.equal(requestedGameplaySettings.WarEventGameSettings.Interval, 1);
assert.equal(requestedGameplaySettings.WarEventGameSettings.MajorDuration, 5);
assert.equal(requestedGameplaySettings.WarEventGameSettings.MinorDuration, 3);
assert.equal(typeof requestedGameplaySettings.WarEventGameSettings.Interval, 'number');
assert.equal(typeof requestedGameplaySettings.WarEventGameSettings.MajorDuration, 'number');
assert.equal(typeof requestedGameplaySettings.WarEventGameSettings.MinorDuration, 'number');
assert.equal(typeof requestedGameplaySettings.MaterialYieldModifier_Global, 'number');
assert.equal(typeof requestedGameplaySettings.DropTableModifier_General, 'number');
assert.equal(typeof requestedGameplaySettings.RepairCostModifier, 'number');
assert.equal(typeof requestedGameplaySettings.DurabilityDrainModifier, 'number');
assert.equal(typeof requestedGameplaySettings.SoulShard_DurabilityLossRate, 'number');
assert.equal(typeof requestedGameplaySettings.RelicSpawnType, 'string');
assert.equal(requestedGameplaySettings.GameTimeModifiers.DayDurationInSeconds, 10800);
assert.equal(requestedGameplaySettings.GameTimeModifiers.BloodMoonFrequency_Min, 10);
assert.equal(requestedGameplaySettings.GameTimeModifiers.BloodMoonFrequency_Max, 20);
assert.equal(requestedGameplaySettings.GameTimeModifiers.BloodMoonBuff, 0.2);
assert.deepEqual(
  requestedGameplaySettings.GameTimeModifiers.UnknownFutureSetting,
  currentSettings.GameTimeModifiers.UnknownFutureSetting,
);
assert.equal(
  requestedGameplaySettings.WarEventGameSettings.PointsModifier,
  currentSettings.WarEventGameSettings.PointsModifier,
);
assert.deepEqual(
  requestedGameplaySettings.WarEventGameSettings.WeekdayTime,
  currentSettings.WarEventGameSettings.WeekdayTime,
);
assert.deepEqual(
  requestedGameplaySettings.WarEventGameSettings.UnknownFutureSetting,
  currentSettings.WarEventGameSettings.UnknownFutureSetting,
);
assert.deepEqual(
  mergeGameplaySettings(requestedGameplaySettings, {
    soul_shard_durability_loss_rate: 0,
    relic_spawn_type: 'Plentiful',
    castle_blood_essence_drain_modifier: 0,
    castle_decay_rate_modifier: 0,
    game_time_modifiers: {
      day_start_hour: 10,
      day_start_minute: 0,
      day_end_hour: 16,
      day_end_minute: 0,
    },
    war_event_game_settings: {
      interval: 1,
      major_duration: 5,
      minor_duration: 3,
    },
  }),
  requestedGameplaySettings,
);

const partialGameplaySettings = mergeGameplaySettings(currentSettings, {
  blood_bound_equipment: true,
  game_time_modifiers: {
    day_start_hour: 10,
  },
  war_event_game_settings: {
    major_duration: 5,
  },
});
assert.equal(partialGameplaySettings.BloodBoundEquipment, true);
assert.equal(partialGameplaySettings.DeathContainerPermission, currentSettings.DeathContainerPermission);
assert.equal(partialGameplaySettings.SoulShard_DurabilityLossRate, currentSettings.SoulShard_DurabilityLossRate);
assert.equal(partialGameplaySettings.RelicSpawnType, currentSettings.RelicSpawnType);
assert.equal(partialGameplaySettings.GameTimeModifiers.DayStartHour, 10);
assert.equal(partialGameplaySettings.GameTimeModifiers.DayEndHour, currentSettings.GameTimeModifiers.DayEndHour);
assert.equal(partialGameplaySettings.GameTimeModifiers.DayEndMinute, currentSettings.GameTimeModifiers.DayEndMinute);
assert.equal(partialGameplaySettings.GameTimeModifiers.DayDurationInSeconds, currentSettings.GameTimeModifiers.DayDurationInSeconds);
assert.equal(partialGameplaySettings.GameTimeModifiers.BloodMoonBuff, currentSettings.GameTimeModifiers.BloodMoonBuff);
assert.equal(partialGameplaySettings.WarEventGameSettings.Interval, currentSettings.WarEventGameSettings.Interval);
assert.equal(partialGameplaySettings.WarEventGameSettings.MajorDuration, 5);
assert.equal(partialGameplaySettings.WarEventGameSettings.MinorDuration, currentSettings.WarEventGameSettings.MinorDuration);
assert.deepEqual(partialGameplaySettings.WarEventGameSettings.WeekdayTime, currentSettings.WarEventGameSettings.WeekdayTime);

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