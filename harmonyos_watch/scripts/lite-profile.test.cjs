const test = require('node:test');
const assert = require('node:assert/strict');
const { normalize } = require('./lite-profile.cjs');

function generatedProfile() {
  return {
    app: {
      bundleName: 'com.geekpie.techpie.watch', vendor: 'geekpie',
      version: { code: 1, name: '0.1.0' }, appEnvironments: [],
      apiVersion: { compatible: 50100018, target: 50100018, compileSdkVersion: '26.0.0' }
    },
    deviceConfig: { default: { debug: true }, liteWearable: { keepAlive: false } },
    module: {
      deviceType: ['liteWearable'], package: 'com.example.myapplication', mainAbility: '.MainAbility',
      distro: { deliveryWithInstall: true, moduleName: 'entry', moduleType: 'entry' },
      abilities: [{ name: '.MainAbility', label: '$string:app_name', labelId: 16777217,
        icon: '$media:icon', iconId: 16777218,
        description: '$string:app_description', descriptionId: 16777219, type: 'page' }],
      js: [{ name: '.MainAbility', pages: ['pages/index/index'] }]
    }
  };
}

test('SDK 26 profile becomes Lite API 18 without changing app identity or entry', () => {
  const source = generatedProfile();
  const output = normalize(source, '5.1.0(18)', '5.1.0(18)');
  assert.deepEqual(output.app.apiVersion, { compatible: 18, target: 18, releaseType: 'Release' });
  assert.equal(output.app.bundleName, source.app.bundleName);
  assert.deepEqual(output.app.version, source.app.version);
  assert.deepEqual(output.module.js, source.module.js);
  assert.equal(output.module.abilities[0].label, '$string:app_name');
  assert.deepEqual(output.deviceConfig, { default: {}, liteWearable: { keepAlive: false } });
  assert.equal('appEnvironments' in output.app, false);
  assert.equal('package' in output.module, false);
  for (const id of ['labelId', 'iconId', 'descriptionId']) {
    assert.equal(output.module.abilities[0][id], source.module.abilities[0][id]);
  }
  assert.equal(source.app.apiVersion.compatible, 50100018);
});

test('rejects compiled resource references without their generated IDs', () => {
  for (const id of ['labelId', 'iconId', 'descriptionId']) {
    const source = generatedProfile();
    delete source.module.abilities[0][id];
    assert.throws(() => normalize(source, 10, 10), new RegExp(id));
  }
});

test('rejects non-Lite devices and invalid API ranges', () => {
  const phone = generatedProfile();
  phone.module.deviceType = ['phone'];
  assert.throws(() => normalize(phone, 18, 18));
  assert.throws(() => normalize(generatedProfile(), 20, 18));
});

test('API 10 comparison build reads the declared range rather than retaining API 18', () => {
  const output = normalize(generatedProfile(), '4.0.0(10)', '4.0.0(10)');
  assert.deepEqual(output.app.apiVersion, { compatible: 10, target: 10, releaseType: 'Release' });
});
