const fs = require('fs');
const src = fs.readFileSync(__dirname + '/../TodoDoc.js', 'utf8')
  .replace('.pragma library', '');
const T = {};
new Function('exports', src + '\n;Object.assign(exports,{parse,counts,setChecked,setTaskText,removeTask,appendTask,matches});')(T);

let pass = 0, fail = 0;
function eq(name, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g === w) { pass++; console.log('  ok   ' + name); }
  else { fail++; console.log('  FAIL ' + name + '\n    got  ' + g + '\n    want ' + w); }
}

const doc = [
  '---',
  'title: Work',
  '---',
  '',
  '# Work',
  '',
  'Some prose with a [link](http://x) in it.',
  '',
  '- [ ] Fix the deploy script',
  '- [x] Renew domain',
  '  - [ ] Nested subtask',
  '* [X] Upper-case done marker',
  '',
  '```sh',
  '- [ ] fenced, not a task',
  '```',
  '',
  '- not a task, no checkbox',
  ''
].join('\n');

console.log('parse');
const tasks = T.parse(doc);
eq('task count (fence excluded)', tasks.length, 4);
eq('lines', tasks.map(t => t.line), [8, 9, 10, 11]);
eq('checked flags', tasks.map(t => t.checked), [false, true, false, true]);
eq('indent of nested', tasks[2].indent, 2);
eq('text', tasks[0].text, 'Fix the deploy script');
eq('counts', T.counts(doc), { total: 4, done: 2 });

console.log('setChecked');
let out = T.setChecked(doc, 8, true);
eq('toggles only that line', out.split('\n')[8], '- [x] Fix the deploy script');
eq('rest of doc byte-identical',
   out.split('\n').filter((l, i) => i !== 8).join('\n'),
   doc.split('\n').filter((l, i) => i !== 8).join('\n'));
eq('preserves nested indent + bullet', T.setChecked(doc, 10, true).split('\n')[10], '  - [x] Nested subtask');
eq('preserves * bullet + case', T.setChecked(doc, 11, false).split('\n')[11], '* [ ] Upper-case done marker');
eq('non-task line refused', T.setChecked(doc, 6, true), null);

console.log('setTaskText');
eq('rewrites body only', T.setTaskText(doc, 9, 'Renew the domain').split('\n')[9], '- [x] Renew the domain');
eq('keeps nested prefix', T.setTaskText(doc, 10, 'Other').split('\n')[10], '  - [ ] Other');
eq('strips newlines', T.setTaskText(doc, 8, 'a\nb').split('\n')[8], '- [ ] a b');
eq('empty body refused', T.setTaskText(doc, 8, '   '), null);

console.log('removeTask');
out = T.removeTask(doc, 9);
eq('one line shorter', out.split('\n').length, doc.split('\n').length - 1);
eq('removed the right line', out.split('\n')[9], '  - [ ] Nested subtask');
eq('non-task line refused', T.removeTask(doc, 6), null);

console.log('appendTask');
const r = T.appendTask(doc, 'Book flights');
eq('inserted after last task', r.line, 12);
eq('inherits * bullet from last task', r.text.split('\n')[12], '* [ ] Book flights');
eq('trailing newline preserved', r.text.endsWith('\n'), true);
eq('prose untouched', r.text.split('\n').slice(0, 12).join('\n'), doc.split('\n').slice(0, 12).join('\n'));

const noTasks = '# Notes\n\nJust prose.\n';
const r2 = T.appendTask(noTasks, 'First task');
eq('empty-list file gets a task at the end', r2.text, '# Notes\n\nJust prose.\n- [ ] First task\n');

const noTrailingNl = '# Notes';
eq('no trailing newline stays that way', T.appendTask(noTrailingNl, 'x').text, '# Notes\n- [ ] x');
eq('empty file', T.appendTask('', 'x').text, '- [ ] x\n');
eq('empty body refused', T.appendTask(doc, '  '), null);

console.log('matches');
eq('empty filter matches', T.matches({ text: 'anything' }, ''), true);
eq('case-insensitive substring', T.matches({ text: 'Fix the DEPLOY script' }, 'deploy'), true);
eq('no match', T.matches({ text: 'abc' }, 'zzz'), false);

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
