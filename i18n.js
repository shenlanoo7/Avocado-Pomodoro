// UI copy only: task names, note drafts and log contents are never translated.
(function () {
  const chinese = {
    'Avocado Pomodoro':'牛油果番茄钟','Pomodoro Settings':'番茄钟设置','Obsidian Checklist':'Obsidian 清单',
    'Rest':'休息','Keep Going':'别停','TIME IS UP':'时间到','Rest or keep your flow':'休息一下，或继续专注','EXTRA FOCUS':'继续专注',
    'Rest or keep going at the bell':'到时选择休息或别停','One small step. You have got this.':'先迈出一小步，你可以的。',
    'Focus prompts':'专注提示语','One prompt per line':'每行输入一条提示语','One prompt per line. Changes save automatically.':'每行一条，修改后自动保存。','At the bell, choose Rest or Keep Going.':'到时选择“休息”或“别停”。',
    'SETTINGS':'设置','Skin':'皮肤','Avocado':'牛油果','Kirby':'卡比','Size':'大小','Completion sound':'完成提示音',
    'Language':'界面语言','On':'开','Off':'关','Done':'完成','Double-click to hide · drag to move':'双击隐藏 · 拖动移动',
    'Choose focus minutes on Start.':'开始前选择专注时长。','Focus ends → 5-minute rest.':'专注结束 → 休息 5 分钟。',
    'Rest ends → start next focus manually.':'休息结束 → 手动开始下一次专注。',
    'ONE MORE BITE':'再专注一会儿','What will you focus on?':'这次想专注做什么？','Name your session':'输入专注名称',
    'Minutes':'分钟','5 MIN REST AFTER FOCUS':'专注后休息 5 分钟','Start Focus':'开始专注','Start':'开始','Notes':'笔记',
    'Finish the current timer before starting another task':'请先结束当前计时，再开始其他任务',
    'FOCUS':'专注','REST':'休息','Pause note (optional)':'暂停笔记（可选）','Save this pause without ending the session':'保存暂停笔记，不结束专注',
    'Save Note':'保存笔记','Saved':'已保存','Pause':'暂停','Resume':'继续','End':'结束','End session and record a note':'结束专注并记录笔记',
    'COMPLETED':'专注完成','Session note (optional)':'专注笔记（可选）','Add a note (optional)':'添加笔记（可选）',
    'Save':'保存','Skip':'跳过','Timer':'计时器','NICE WORK!':'做得不错！','Rest your eyes and mind':'放松眼睛，休息一下',
    'Start Rest':'开始休息','Next':'下一次','REST COMPLETE':'休息结束','Checklist':'清单','Settings…':'设置…',
    'Choose a vault task or custom name':'选择笔记库任务或输入自定义名称','Search tasks':'搜索任务','Use custom name':'使用自定义名称',
    'Loading tasks…':'正在加载任务…','No matching tasks · clear search to see all':'没有匹配任务 · 清空搜索以查看全部',
    'No open checklist tasks · use a custom name':'没有未完成任务 · 可使用自定义名称','Check access to the checklist vault':'请检查笔记库访问权限',
    'Tasks could not load: {error} · use a custom name':'任务加载失败：{error} · 可使用自定义名称',
    'Pause note saved':'暂停笔记已保存','Save failed: {error}':'保存失败：{error}','Saved to pomodoro-log.md':'已保存到 pomodoro-log.md',
    'Open the desktop app to save notes':'请在桌面应用中保存笔记','Notes ({count})':'笔记（{count}）',
    '{minutes} MIN · {time} DONE':'{minutes} 分钟 · 已完成 {time}','{phase} {time} · {count} {notes}':'{phase} {time} · {count} 条笔记',
    'Pixel Kirby. Drag to move. Double-click to hide.':'像素卡比。拖动移动，双击隐藏。',
    'Pixel avocado. Drag to move. Double-click to hide.':'像素牛油果。拖动移动，双击隐藏。',
    'CHECKLIST':'任务清单','Note':'笔记','All notes':'全部笔记','Task filter':'任务筛选','All':'全部','Open':'未完成',
    'Refresh':'刷新','Loading tasks from Obsidian…':'正在从 Obsidian 加载任务…','Reading vault…':'正在读取笔记库…',
    'Hide checklist':'隐藏清单','TASKS':'任务','Saving to Obsidian…':'正在保存到 Obsidian…','No tasks match this view.':'没有符合筛选条件的任务。',
    'No Markdown tasks found.':'未找到 Markdown 任务。','Unable to sync. Refresh and retry.':'无法同步，请刷新后重试。',
    '{count} / {total} tasks · Synced {time}':'{count} / {total} 个任务 · 已同步 {time}'
  };
  let language = localStorage.getItem('avocado.language') === 'zh' ? 'zh' : 'en';
  const originals = new Map();
  function remember() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let node; (node = walker.nextNode());) {
      if (node.parentElement.closest('script,style,textarea')) continue;
      const key = node.textContent.trim();
      if (chinese[key]) originals.set(node, key);
    }
    for (const element of document.querySelectorAll('[placeholder],[aria-label],[title]')) {
      for (const attr of ['placeholder','aria-label','title']) {
        const key = element.getAttribute(attr);
        if (chinese[key]) { element.dataset['i18n'+attr.replace(/-([a-z])/g,(_,c)=>c.toUpperCase())] = key; }
      }
    }
  }
  window.t = (key, values = {}) => (language === 'zh' ? chinese[key] || key : key).replace(/\{(\w+)\}/g, (_, name) => String(values[name] ?? ''));
  window.uiLanguage = () => language;
  window.applyLanguage = (value) => {
    language = value === 'zh' ? 'zh' : 'en';
    localStorage.setItem('avocado.language', language);
    document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
    for (const [node,key] of originals) if (node.isConnected) node.textContent = t(key);
    for (const element of document.querySelectorAll('[placeholder],[aria-label],[title]')) {
      for (const attr of ['placeholder','aria-label','title']) {
        const key = element.dataset['i18n'+attr.replace(/-([a-z])/g,(_,c)=>c.toUpperCase())];
        if (key) element.setAttribute(attr,t(key));
      }
    }
    document.title = t(document.documentElement.dataset.title);
    document.dispatchEvent(new Event('languagechange'));
  };
  document.documentElement.dataset.title = document.title;
  remember();
  applyLanguage(language);
  window.addEventListener('storage', event => { if (event.key === 'avocado.language') applyLanguage(event.newValue); });
})();
