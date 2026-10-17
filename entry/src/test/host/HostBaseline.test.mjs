import test from 'node:test';
import assert from 'node:assert/strict';

test('host runner baseline: arithmetic', () => {
  assert.equal(2 + 2, 4);
});

test('host runner baseline: strings', () => {
  assert.equal('YAOCORE'.toLowerCase(), 'yaocore');
});
