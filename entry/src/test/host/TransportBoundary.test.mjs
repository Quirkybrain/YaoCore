/*
 * YaoCore T-11 production-boundary checks (SC-11, D-04, D-07).
 * Producer: agent:implementation-engineer | Task: T-11 / wp-035-transport
 * Contract: DES-A §2.2 D-04/D-07, §17.3; project-constraints SC-11/D-08.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(HERE, '../../../..');
const MAIN = path.join(REPO_ROOT, 'entry/src/main/ets');

const walk = (directory) => {
  const files = [];
  for (const entry of readdirSync(directory)) {
    const full = path.join(directory, entry);
    if (statSync(full).isDirectory()) {
      files.push(...walk(full));
    } else if (full.endsWith('.ets')) {
      files.push(full);
    }
  }
  return files;
};

const specifiers = (file) => {
  const text = readFileSync(file, 'utf8');
  const found = [];
  const pattern = /(?:from\s+|import\s*)['"]([^'"]+)['"]/g;
  let match = pattern.exec(text);
  while (match !== null) {
    found.push(match[1]);
    match = pattern.exec(text);
  }
  return found;
};

test('T11_noProductionFileImportsC20MockOrOhosTest', () => {
  const offenders = [];
  const mockDirectory = path.join(MAIN, 'service/mock') + path.sep;
  for (const file of walk(MAIN)) {
    const insideMock = file.startsWith(mockDirectory);
    for (const specifier of specifiers(file)) {
      if (specifier.includes('ohosTest')) {
        offenders.push(`${path.relative(REPO_ROOT, file)} -> ${specifier}`);
        continue;
      }
      if (insideMock) {
        continue;
      }
      if (specifier.includes('service/mock') || specifier.includes('/mock/') ||
        specifier.includes('MockGatewayService') ||
        specifier.includes('MockBleProvisioningClient') ||
        specifier.includes('MockScenario')) {
        offenders.push(`${path.relative(REPO_ROOT, file)} -> ${specifier}`);
      }
    }
  }
  assert.deepEqual(offenders, []);
});

test('T11_mockFilesDeclareTestOnlyBoundary', () => {
  for (const name of ['MockGatewayService.ets', 'MockBleProvisioningClient.ets',
    'MockScenario.ets']) {
    const file = path.join(REPO_ROOT, 'entry/src/main/ets/service/mock', name);
    const text = readFileSync(file, 'utf8');
    assert.match(text, /TEST ONLY/, `${name} must declare the TEST ONLY boundary`);
  }
});

test('T11_pureGatewayLogicHasNoPlatformImport', () => {
  const pure = [
    'contracts/GatewayTransportPorts.ets',
    'model/GatewayTransportModels.ets',
    'contracts/DiscoveryTransport.ets',
    'model/DiscoveryModels.ets',
    'contracts/GatewayPorts.ets',
    'model/InvitedGateway.ets',
    'contracts/BleProvisioningPorts.ets',
    'model/ProvisioningModels.ets',
    'model/GattEndpointMap.ets',
    'service/gateway/GatewayRequestPolicy.ets',
    'service/gateway/LocalGatewayService.ets',
    'service/gateway/ManualAddressPolicy.ets',
    'service/gateway/ProbeBackoff.ets',
    'service/gateway/GatewayDiscoveryService.ets',
    'service/mock/MockGatewayService.ets',
    'service/mock/MockBleProvisioningClient.ets',
    'service/mock/MockScenario.ets',
    'service/ble/BleSupport.ets',
    'service/ble/Protobuf.ets',
    'service/ble/ProtocommCodec.ets',
    'service/ble/GattRequestQueue.ets',
    'service/ble/GattChannel.ets',
    'service/ble/ProtoVerParser.ets',
    'service/ble/Security1Session.ets',
    'service/ble/IdentityNegotiator.ets',
    'service/ble/WifiProvisioningFlow.ets',
    'service/ble/ProvisioningStateMachine.ets',
    'service/ble/BindingProbe.ets',
    'service/ble/BleProvisioningService.ets',
  ];
  const offenders = [];
  for (const relative of pure) {
    for (const specifier of specifiers(path.join(MAIN, relative))) {
      if (specifier.startsWith('@ohos.') || specifier.startsWith('@kit.')) {
        offenders.push(`${relative} -> ${specifier}`);
      }
    }
  }
  assert.deepEqual(offenders, []);
});
