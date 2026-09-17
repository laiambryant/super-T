const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync(`${__dirname}/../Config.js`, 'utf8').replace('.pragma library', '');
const { resolve, fromShell } = new Function(`${source}; return {resolve, fromShell};`)();
const home = '/tmp/home with spaces';
assert.equal(resolve(undefined, home).path, `${home}/Documents/todos`);
assert.equal(resolve('~/vault/', home).path, `${home}/vault`);
assert.equal(resolve('~', home).path, home);
assert.equal(resolve('/', home).path, '/');
assert.equal(resolve('///', home).path, '/');
assert.equal(resolve('/tmp/vault with spaces', home).ok, true);
for (const bad of [null, false, 0, {}, [], '', ' ', 'relative', '~alice/vault', '/tmp/\nfoo'])
  assert.equal(resolve(bad, home).ok, false, `must reject ${JSON.stringify(bad)}`);
for (const bad of ['{', '[]', 'null', '{"plugins":{}}'])
  assert.equal(fromShell(bad, 'liambryant.todo').ok, false);
const missing = fromShell('{"plugins":[]}', 'liambryant.todo');
assert.equal(missing.ok, true);
assert.equal(missing.value, undefined);
for (const dir of ['', null, 99, {}]) {
  const read = fromShell(JSON.stringify({plugins:[{id:'liambryant.todo', dir}]}), 'liambryant.todo');
  assert.equal(read.ok, true);
  assert.deepEqual(read.value, dir);
  assert.equal(resolve(read.value, home).ok, false);
}
console.log('Config: omission, type, syntax, and path validation passed');
