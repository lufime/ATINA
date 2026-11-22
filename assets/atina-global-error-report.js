/* ATINA — reporte transversal de erros. Sem dependências externas. */
(function(){
 'use strict';
 if(document.getElementById('atinaGlobalReportRoot'))return;
 const css=`
 #atinaGlobalReportButton{position:fixed;z-index:12000;right:max(14px,env(safe-area-inset-right));bottom:max(14px,env(safe-area-inset-bottom));border:2px solid #d3ad68;border-radius:999px;background:#182c43;color:#fff;padding:12px 16px;font:800 14px system-ui;box-shadow:0 8px 26px #0007}
 #atinaGlobalReportOverlay{position:fixed;z-index:12001;inset:0;background:#06101bd9;display:none;align-items:center;justify-content:center;padding:max(12px,env(safe-area-inset-top)) 12px max(12px,env(safe-area-inset-bottom));}
 #atinaGlobalReportOverlay.open{display:flex}
 #atinaGlobalReportDialog{width:min(100%,600px);max-height:calc(100dvh - 24px);overflow:auto;border:2px solid #d3ad68;border-radius:18px;background:#152b42;color:#f3f0e8;padding:16px;box-shadow:0 18px 48px #0009}
 #atinaGlobalReportDialog h2{margin:4px 0 12px;font-size:22px}
 #atinaGlobalReportDialog label{display:block;font-weight:750;margin:12px 0 6px}
 #atinaGlobalReportDialog select,#atinaGlobalReportDialog textarea,#atinaGlobalReportDialog input[type=file]{display:block;width:100%;min-width:0;max-width:100%;box-sizing:border-box;border:1px solid #52657b;border-radius:11px;background:#0d1a2a;color:#fff;padding:12px;font:inherit}
 #atinaGlobalReportDialog textarea{resize:vertical;min-height:110px}
 #atinaGlobalReportDialog button{width:100%;min-height:46px;border:1px solid #3e536b;border-radius:11px;padding:10px;background:#20374f;color:#fff;font:750 14px system-ui;margin-top:8px}
 #atinaGlobalReportDialog button.primary{background:#d3ad68;color:#18212c;border-color:#d3ad68}
 #atinaGlobalReportDialog button:disabled{opacity:.6}
 #atinaGlobalReportContext{font-size:12px;line-height:1.45;color:#d6dfeb;border:1px solid #425b74;background:#102238;border-radius:10px;padding:10px;white-space:pre-wrap;overflow-wrap:anywhere}
 #atinaGlobalReportPreview{display:block;width:100%;max-height:240px;object-fit:contain;margin-top:8px;border-radius:10px}
 #atinaGlobalReportStatus{min-height:24px;margin:8px 0;font-size:13px;font-weight:750}
 #atinaSoloReportOpen,#atinaSoloReportPanel{display:none!important}
 @media(max-width:420px){#atinaGlobalReportDialog{padding:12px;border-radius:14px}#atinaGlobalReportDialog h2{font-size:19px}#atinaGlobalReportButton{padding:10px 13px;font-size:13px}}
 `;
 const style=document.createElement('style');style.textContent=css;document.head.appendChild(style);
 const root=document.createElement('div');root.id='atinaGlobalReportRoot';
 root.innerHTML=`
 <button id="atinaGlobalReportButton" type="button" aria-haspopup="dialog">🐞 Reportar erro</button>
 <div id="atinaGlobalReportOverlay" role="presentation">
  <section id="atinaGlobalReportDialog" role="dialog" aria-modal="true" aria-labelledby="atinaGlobalReportTitle">
   <div style="display:flex;align-items:center;justify-content:space-between;gap:10px">
    <h2 id="atinaGlobalReportTitle">🐞 Reportar erro</h2>
    <button type="button" id="atinaGlobalReportClose" aria-label="Fechar reporte" style="width:auto;min-width:44px;margin:0">✕</button>
   </div>
   <p style="font-size:13px;color:#bac8d7;margin:4px 0 12px">O contexto do jogo é anexado automaticamente. Não incluas dados pessoais.</p>
   <div id="atinaGlobalReportContext"></div>
   <form id="atinaGlobalReportForm">
    <label for="atinaGlobalReportCategory">Categoria</label>
    <select id="atinaGlobalReportCategory">
     <option value="visual">Visual</option><option value="game">Jogo</option><option value="points_xp">Pontuação/XP</option><option value="technical">Técnico</option><option value="other">Outro</option>
    </select>
    <label for="atinaGlobalReportDescription">Descrição (mínimo 20 caracteres)</label>
    <textarea id="atinaGlobalReportDescription" maxlength="2000" required placeholder="Descreve o problema e o que esperavas que acontecesse."></textarea>
    <label for="atinaGlobalReportScreenshot">Screenshot (opcional, até 3 MB)</label>
    <input id="atinaGlobalReportScreenshot" type="file" accept="image/png,image/jpeg,image/webp">
    <button type="button" id="atinaGlobalReportCapture">📷 Capturar screenshot</button>
    <img id="atinaGlobalReportPreview" alt="Pré-visualização da screenshot" hidden>
    <button type="button" id="atinaGlobalReportRemoveScreenshot">Remover screenshot</button>
    <button type="submit" id="atinaGlobalReportSubmit" class="primary">Enviar reporte</button>
    <p id="atinaGlobalReportStatus" role="status" aria-live="polite"></p>
   </form>
   <button type="button" id="atinaGlobalReportResume">Fechar e voltar ao jogo</button>
  </section>
 </div>`;
 document.body.appendChild(root);
 const $=id=>document.getElementById(id);
 const overlay=$('atinaGlobalReportOverlay'),form=$('atinaGlobalReportForm'),status=$('atinaGlobalReportStatus'),submit=$('atinaGlobalReportSubmit');
 const MAX=3*1024*1024;let screenshot=null,pausedSolo=false;
 const safe=(v,max=120)=>String(v??'').replace(/[\r\n]+/g,' ').trim().slice(0,max);
 function visibleScreen(){const ids=['home','game','mimicaGame','result','rankingPage','networkLobby'];return ids.find(id=>{const el=document.getElementById(id);return el&&!el.hidden&&!el.classList.contains('hidden')&&getComputedStyle(el).display!=='none'})||'unknown';}
 function gameContext(){
  const screen=visibleScreen(),currentMode=safe(typeof mode!=='undefined'?mode:'unknown',40),room=typeof networkRoom!=='undefined'&&networkRoom?networkRoom:null;
  let timer='';if(screen==='game'&&typeof timeLeft!=='undefined'){const remaining=pausedSolo&&typeof atinaSoloReportRemaining!=='undefined'?atinaSoloReportRemaining:timerDeadline?Math.max(0,Math.ceil((timerDeadline-Date.now())/1000)):timeLeft;timer=safe(remaining,20)+'s'}else if(screen==='mimicaGame')timer=safe($('mimeTimer')?.textContent,30);
  const category=screen==='game'?safe($('category')?.textContent,100):screen==='mimicaGame'?safe($('mimeCategory')?.textContent,100):'';
  const round=screen==='game'&&typeof pos!=='undefined'?String(pos+1):screen==='mimicaGame'?safe($('mimeRound')?.textContent,40):'';
  const roomId=room?safe(room.room_id,80):'';
  const version=(()=>{const meta=document.querySelector('meta[name="atina-game-version"]');return meta?safe(meta.content,40):''})();
  const question=screen==='game'?safe($('question')?.textContent,220):'';
  const clues=screen==='game'?safe($('clues')?.textContent,480):'';
  const score=screen==='game'&&typeof scores!=='undefined'?safe(scores.join(' / '),40):'';
  const streak=screen==='game'&&typeof correctStreak!=='undefined'?safe(correctStreak,30):'';
  return {screen,mode:currentMode,room:roomId||undefined,round:round||undefined,category:category||undefined,timer:timer||undefined,question:question||undefined,clues:clues||undefined,score:score||undefined,streak:streak||undefined,version:version||undefined,paused:pausedSolo};
 }
 function contextText(ctx){return ['Contexto automático do jogo:', 'Ecrã: '+ctx.screen,'Modo: '+ctx.mode,ctx.room?'Sala: '+ctx.room:'',ctx.round?'Ronda: '+ctx.round:'',ctx.category?'Categoria: '+ctx.category:'',ctx.timer?'Tempo visível: '+ctx.timer:'',ctx.question?'Desafio: '+ctx.question:'',ctx.clues?'Pistas visíveis: '+ctx.clues:'',ctx.score?'Pontuação: '+ctx.score:'',ctx.streak?'Sequência: '+ctx.streak:'',ctx.version?'Versão: '+ctx.version:''].filter(Boolean).join('\n');}
 function pauseSolo(){
  if(visibleScreen()!=='game'||typeof mode==='undefined'||mode!=='solo'||typeof atinaSoloReportOpen!=='function')return false;
  if(typeof atinaSoloReportPaused!=='undefined'&&atinaSoloReportPaused)return false;
  atinaSoloReportOpen();pausedSolo=typeof atinaSoloReportPaused!=='undefined'&&atinaSoloReportPaused;return pausedSolo;
 }
 function resumeSolo(){if(pausedSolo&&typeof atinaSoloReportResume==='function')atinaSoloReportResume();pausedSolo=false;}
 function open(){pausedSolo=pauseSolo();$('atinaGlobalReportContext').textContent=contextText(gameContext());overlay.classList.add('open');$('atinaGlobalReportDescription').focus();status.textContent=pausedSolo?'Relógio pausado.':'Contexto anexado ao reporte.';}
 function close(){overlay.classList.remove('open');resumeSolo();}
 function clearImage(){screenshot=null;$('atinaGlobalReportScreenshot').value='';$('atinaGlobalReportPreview').removeAttribute('src');$('atinaGlobalReportPreview').hidden=true;}
 function attach(file){if(!file){clearImage();return}if(!['image/png','image/jpeg','image/webp'].includes(file.type)){clearImage();status.textContent='Formato inválido. Usa PNG, JPG ou WebP.';return}if(file.size>MAX){clearImage();status.textContent='Screenshot excede 3 MB.';return}const reader=new FileReader();reader.onload=()=>{const data=String(reader.result||''),comma=data.indexOf(',');if(comma<0){clearImage();status.textContent='Screenshot inválida.';return}screenshot={content_type:file.type,base64:data.slice(comma+1)};$('atinaGlobalReportPreview').src=data;$('atinaGlobalReportPreview').hidden=false};reader.onerror=()=>{clearImage();status.textContent='Não foi possível ler a imagem.'};reader.readAsDataURL(file)}
 $('atinaGlobalReportScreenshot').addEventListener('change',e=>attach(e.target.files?.[0]));
 $('atinaGlobalReportRemoveScreenshot').addEventListener('click',clearImage);
 $('atinaGlobalReportCapture').addEventListener('click',async()=>{const button=$('atinaGlobalReportCapture');if(!navigator.mediaDevices?.getDisplayMedia){status.textContent='Captura de ecrã não suportada neste navegador.';return}button.disabled=true;status.textContent='Escolhe o ecrã ou separador do ATINA…';let stream=null;try{stream=await navigator.mediaDevices.getDisplayMedia({video:{frameRate:1},audio:false});const video=document.createElement('video');video.srcObject=stream;video.muted=true;video.playsInline=true;await new Promise((resolve,reject)=>{video.onloadedmetadata=resolve;video.onerror=reject});await video.play();const w=video.videoWidth||1280,h=video.videoHeight||720,scale=Math.min(1,1280/w,720/h),canvas=document.createElement('canvas');canvas.width=Math.round(w*scale);canvas.height=Math.round(h*scale);canvas.getContext('2d')?.drawImage(video,0,0,canvas.width,canvas.height);const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.82));if(!blob)throw new Error('Não foi possível gerar a captura.');if(blob.size>MAX)throw new Error('Screenshot excede 3 MB.');const reader=new FileReader();await new Promise((resolve,reject)=>{reader.onload=resolve;reader.onerror=reject;reader.readAsDataURL(blob)});const data=String(reader.result||''),comma=data.indexOf(',');screenshot={content_type:'image/jpeg',base64:data.slice(comma+1)};$('atinaGlobalReportPreview').src=data;$('atinaGlobalReportPreview').hidden=false;status.textContent='Screenshot anexada.'}catch(err){status.textContent=err?.message||'Captura cancelada ou falhou.'}finally{stream?.getTracks().forEach(t=>t.stop());button.disabled=false}});
 $('atinaGlobalReportButton').addEventListener('click',open);$('atinaGlobalReportClose').addEventListener('click',close);$('atinaGlobalReportResume').addEventListener('click',close);
 overlay.addEventListener('click',e=>{if(e.target===overlay)close()});document.addEventListener('keydown',e=>{if(e.key==='Escape'&&overlay.classList.contains('open'))close()});
 form.addEventListener('submit',async e=>{e.preventDefault();const user=$('atinaGlobalReportDescription').value.trim();if(user.length<20){status.textContent='A descrição deve ter pelo menos 20 caracteres.';return}submit.disabled=true;status.textContent='A enviar reporte…';try{const ctx=gameContext(),details=contextText(ctx),description=(user.slice(0,1450)+'\n\n'+details).slice(0,2000);const endpoint=typeof ATINA_GAME_SUPABASE_URL!=='undefined'?ATINA_GAME_SUPABASE_URL+'/functions/v1/atina-error-reports-submit':'';const key=typeof ATINA_GAME_SUPABASE_KEY!=='undefined'?ATINA_GAME_SUPABASE_KEY:'';if(!endpoint||!key)throw new Error('Serviço de reporte indisponível.');const response=await fetch(endpoint,{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({nickname:(localStorage.getItem('atinaProgressNicknameV1')||'Visitante').trim().slice(0,40)||'Visitante',category:$('atinaGlobalReportCategory').value,description,game_area:ctx.screen+' · '+ctx.mode,game_version:ctx.version||null,screenshot})});const result=await response.json().catch(()=>({}));if(!response.ok||!result.success)throw new Error(result.error||'Não foi possível enviar o reporte.');status.textContent='Reporte enviado com sucesso. Obrigado!';$('atinaGlobalReportDescription').value='';clearImage();setTimeout(close,500)}catch(err){status.textContent=err?.message||'Falha no envio. A descrição foi mantida para tentares novamente.'}finally{submit.disabled=false}});
})();