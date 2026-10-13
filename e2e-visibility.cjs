const {chromium}=require('/Users/shenlan/.hermes/cache/scratch/pomodoro-qa/node_modules/playwright');
const assert=require('node:assert/strict');
(async()=>{const b=await chromium.launch();try{
  const p=await b.newPage({viewport:{width:247,height:377}});
  await p.addInitScript(()=>{window.messages=[];window.webkit={messageHandlers:{native:{postMessage:p=>messages.push(p)}}};});
  await p.goto('file://'+__dirname+'/index.html');
  const before=await p.locator('.widget').boundingBox();
  for(const skin of ['avocado','kirby']){
    await p.evaluate(skin=>applySkin(skin),skin);
    for(const id of ['body','dial']){
      await p.evaluate(()=>messages=[]);
      await p.locator('#'+id).dispatchEvent('dblclick');
      assert.equal(await p.evaluate(()=>messages.filter(m=>m.action==='hide').length),1,skin+' '+id+' double click hides');
    }
  }
  for(const id of ['name','focusMinutes','start','note','pause','openSettings']){
    await p.evaluate(()=>messages=[]);
    await p.locator('#'+id).dispatchEvent('dblclick');
    assert.equal(await p.evaluate(()=>messages.some(m=>m.action==='hide')),false,id+' retains normal double click');
  }
  await p.evaluate(()=>{$('name').value='Hidden focus';$('start').click();messages=[];});
  const state=await p.evaluate(()=>JSON.stringify(timer));
  await p.locator('#time').dispatchEvent('dblclick');
  assert.equal(await p.evaluate(()=>messages.at(-1).action),'hide');
  assert.equal(await p.evaluate(()=>JSON.stringify(timer)),state,'hiding must not pause/reset timer');
  for(const phase of ['focus','break'])for(const soundOff of [false,true]){
    await p.evaluate(({phase,soundOff})=>{muted=soundOff;timer=new Timer();if(phase==='focus')timer.start('Hidden expiry');else timer.break();timer.deadline=Date.now()-1;messages=[];tickTimer();},{phase,soundOff});
    assert.equal(await p.evaluate(()=>messages.some(m=>m.action==='reveal')),true,phase+' expiry reveals regardless of mute');
    assert.equal(await p.evaluate(()=>messages.some(m=>m.action==='alarm')),!soundOff);
  }
  assert.deepEqual(await p.locator('.widget').boundingBox(),before);
  console.log('PASS both skins double-click hide; controls preserved; timer unchanged; focus/rest completion reveal with sound on/off');
}finally{await b.close();}})().catch(e=>{console.error(e);process.exit(1)});
