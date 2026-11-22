import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const server = createServer(async (request, response) => {
  const pathname = new URL(request.url || '/', 'http://127.0.0.1').pathname;
  if (pathname === '/' || pathname === '/index.html') {
    response.writeHead(200, {'content-type':'text/html; charset=utf-8'});
    response.end(indexHtml);
    return;
  }
  if (pathname.startsWith('/assets/') || pathname === '/atina-server-client.js') {
    try {
      const file = await readFile(new URL('../' + pathname.slice(1), import.meta.url));
      response.writeHead(200, {'content-type':'text/javascript; charset=utf-8'});
      response.end(file);
    } catch {
      response.writeHead(404); response.end('Not found');
    }
    return;
  }
  response.writeHead(404); response.end('Not found');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({headless:true});
try {
  for (const viewport of [{width:320,height:720},{width:390,height:844},{width:1440,height:900}]) {
    const page = await browser.newPage({viewport});
    await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2', route => route.fulfill({
      status:200,contentType:'application/javascript',body:`window.supabase={createClient:()=>({auth:{onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),getSession:async()=>({data:{session:null},error:null}),getUser:async()=>({data:{user:null},error:null}),signOut:async()=>({error:null}),signInWithPassword:async()=>({error:null}),signUp:async()=>({data:{session:null},error:null}),resetPasswordForEmail:async()=>({error:null}),updateUser:async()=>({error:null})},from:()=>({select(){return this},eq(){return this},maybeSingle:async()=>({data:null,error:null}),insert(){return this},update(){return this}}),rpc:async()=>({data:null,error:null})})};`
    }));
    await page.route('https://commons.wikimedia.org/**', route => route.fulfill({status:200,contentType:'application/json',body:'{"query":{"pages":{}}}'}));
    await page.goto(`http://127.0.0.1:${server.address().port}/`,{waitUntil:'load'});
    await page.evaluate(() => {
      const game=document.querySelector('#game');
      if(game){game.classList.remove('hidden');game.hidden=false;game.setAttribute('aria-hidden','false');game.style.setProperty('display','block','important');}
      mode='solo'; networkRoom=false; locked=false; timePenaltyApplied=false;
      autoNextTimeout=null; autoRevealTimeout=null; autoRevealInterval=null;
      timerDeadline=Date.now()+90000; timeLeft=90; timerInterval=null;
    });
    await page.evaluate(() => document.querySelector('#atinaGlobalReportButton')?.click());
    const panel=page.locator('#atinaGlobalReportDialog');
    await panel.waitFor({state:'visible'});
    const dims=await page.evaluate(() => {
      const panel=document.querySelector('#atinaGlobalReportDialog');
      const rect=panel.getBoundingClientRect();
      const category=document.querySelector('#atinaGlobalReportCategory').getBoundingClientRect();
      const description=document.querySelector('#atinaGlobalReportDescription').getBoundingClientRect();
      return {vw:innerWidth,panelWidth:rect.width,panelLeft:rect.left,panelRight:rect.right,panelScroll:panel.scrollWidth,panelClient:panel.clientWidth,categoryWidth:category.width,descriptionWidth:description.width};
    });
    assert.ok(dims.panelWidth <= viewport.width, `report panel wider than viewport at ${viewport.width}px: ${JSON.stringify(dims)}`);
    assert.ok(dims.panelLeft >= 0 && dims.panelRight <= viewport.width, `panel clipped at ${viewport.width}px: ${JSON.stringify(dims)}`);
    assert.ok(dims.categoryWidth <= dims.panelWidth && dims.descriptionWidth <= dims.panelWidth, `form controls overflow panel: ${JSON.stringify(dims)}`);
    assert.ok(dims.panelScroll <= dims.panelClient + 1, `panel has horizontal overflow at ${viewport.width}px: ${JSON.stringify(dims)}`);
    assert.equal(await page.locator('#atinaGlobalReportOverlay').evaluate(el=>el.classList.contains('open')),true);
    assert.equal(await page.evaluate(()=>atinaSoloReportPaused),true,'Solo timer should pause when the global report modal opens');
    await page.locator('#atinaGlobalReportClose').click();
    assert.equal(await page.evaluate(()=>atinaSoloReportPaused),false,'Solo timer should resume when the global report is closed');
    await page.close();
    console.log(`PASS responsive report panel at ${viewport.width}x${viewport.height}`);
  }
} finally {
  await browser.close();
  server.close();
}
