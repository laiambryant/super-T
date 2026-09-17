const fs = require('node:fs');
const src = fs.readFileSync(`${__dirname}/../TodoDoc.js`, 'utf8').replace('.pragma library', '');
const T = new Function(`${src}; return {parse,setChecked,setTaskText,removeTask,appendTask};`)();
const fixtures = [
  '# Title\n\n- [ ] First\n* [X] Done #tag\n',
  '# Title\r\n\r\n- [ ]no gap\r\n  + [X]\ttask\r\n',
  '# Title\r- [ ] mac\r- [ ] final',
  '\uFEFF---\r\ntags: [work]\r\n- [ ] yaml example\r\n---\r\n- [ ] real\r\n',
  '---  \n- [ ] yaml\n... \n- [ ] real\n',
  '````md\n```\n~~~\n- [ ] example\n`````  \n- [ ] real\n',
  '~~~md\n- [ ] example\n~~~\n* [X] real\n',
  '# Notes', '', '\n\n',
  '- [ ] Body\u2028continued\n- [ ] with\vtab\n- [ ] final',
];
console.log(JSON.stringify(fixtures.map(text => {
  const tasks = T.parse(text), line = tasks.length ? tasks[0].line : -1;
  return {text, result:{tasks, checked:T.setChecked(text,line,true), edited:T.setTaskText(text,line,'edited'),
    removed:T.removeTask(text,line), added:T.appendTask(text,'new task')}};
})));
