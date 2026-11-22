(function(){
 const trigger=document.createElement('button');
 trigger.type='button';trigger.textContent='🐞 Reportar erro';trigger.setAttribute('aria-label','Reportar erro em qualquer ecrã do ATINA');
 trigger.style.cssText='position:fixed;right:14px;bottom:calc(14px + env(safe-area-inset-bottom));z-index:9998;border:1px solid #d6b45d;border-radius:14px;padding:12px 14px;background:#17334f;color:#fff;font-weight:800;box-shadow:0 8px 24px #0008';
 const dialog=document.createElement('section');
 dialog.style.cssText='display:none;position:fixed;inset:0;z-index:9999;overflow:auto;background:#07111eeF;padding:16px;align-items:center;justify-content:center';
 dialog.setAttribute('role','dialog');dialog.setAttribute('aria-modal','true');dialog.setAttribute('aria-label','Reportar erro');
 const panel=document.createElement('div');panel.style.cssText='width:min(100%,560px);max-height:100%;overflow:auto;padding:18px;border:2px solid #d6b45d;border-radius:18px;background:#142b43;color:#f3f0e8';
 const title=document.createElement('h2');title.textContent='Reportar erro';panel.append(title);
 const descriptionLabel=document.createElement('label');descriptionLabel.textContent='Descrição (mínimo 20 caracteres)';descriptionLabel.style.cssText='display:block;margin:12px 0 6px;font-weight:700';
 const description=document.createElement('textarea');description.rows=4;description.maxLength=2000;description.placeholder='Descreve o que aconteceu…';description.style.cssText='width:100%;box-sizing:border-box;padding:12px;border-radius:10px;background:#0d1a2a;color:white;border:1px solid #53657b';
 const categoryLabel=document.createElement('label');categoryLabel.textContent='Categoria';categoryLabel.style.cssText='display:block;margin:12px 0 6px;font-weight:700';
 const category=document.createElement('select');category.style.cssText=description.style.cssText;['Visual','Jogo','Pontuação/XP','Técnico','Outro'].forEach(label=>{const option=document.createElement('option');option.textContent=label;category.append(option);});
 const screenshotLabel=document.createElement('label');screenshotLabel.textContent='Screenshot (opcional, PNG/JPG/WebP até 3 MB)';screenshotLabel.style.cssText='display:block;margin:12px 0 6px;font-weight:700';
 const screenshot=document.createElement('input');screenshot.type='file';screenshot.accept='image/png,image/jpeg,image/webp';screenshot.style.cssText='display:block;width:100%;margin:6px 0';
 const status=document.createElement('p');status.setAttribute('role','status');status.style.cssText='min-height:24px;color:#ffdf8a';
 const row=document.createElement('div');row.style.cssText='display:flex;gap:8px;margin-top:12px';
 const send=document.createElement('button');send.type='button';send.textContent='Enviar report';send.style.cssText='flex:1;padding:12px;border:0;border-radius:10px;background:#e9bd61;color:#17202b;font-weight:800';
 const closeButton=document.createElement('button');closeButton.type='button';closeButton.textContent='Fechar';closeButton.style.cssText='padding:12px;border-radius:10px;border:1px solid #456;background:#1a2d44;color:white';
 panel.append(descriptionLabel,description,categoryLabel,category,screenshotLabel,screenshot,status,row);row.append(send,closeButton);dialog.append(panel);document.body.append(trigger,dialog);
 function currentContext(){const screens=['home','game','mimicaGame','result','rankingPage','networkLobby'];const visible=screens.find(id=>{const el=document.getElementById(id);return el&&!el.hidden&&!el.classList.contains('hidden')});const round=document.getElementById('atinaRoundNumber')?.textContent?.trim(),total=document.getElementById('atinaRoundTotal')?.textContent?.trim();return [visible?'ecrã='+visible:'ecrã=desconhecido',round&&total?'ronda='+round+'/'+total:null].filter(Boolean).join(' · ').slice(0,80)||'Report transversal';}
 function close(){dialog.style.display='none';description.value='';screenshot.value='';status.textContent='';}
 trigger.addEventListener('click',()=>{dialog.style.display='flex';description.focus();});
 closeButton.addEventListener('click',close);dialog.addEventListener('click',e=>{if(e.target===dialog)close();});
 send.addEventListener('click',async()=>{const text=description.value.trim();if(text.length<20){status.textContent='A descrição deve ter pelo menos 20 caracteres.';return;}send.disabled=true;status.textContent='A enviar…';try{let screenshotPayload=null;const file=screenshot.files?.[0];if(file){if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>3*1024*1024)throw Error('Screenshot inválida ou superior a 3 MB.');screenshotPayload=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve({content_type:file.type,base64:String(reader.result).split(',')[1]||''});reader.onerror=()=>reject(Error('Não foi possível ler a screenshot.'));reader.readAsDataURL(file);});}
 const labels={'Visual':'visual','Jogo':'game','Pontuação/XP':'points_xp','Técnico':'technical','Outro':'other'};
 const response=await fetch('https://qvvlqrgbtjujsejvenld.supabase.co/functions/v1/atina-error-reports-submit',{method:'POST',headers:{apikey:'sb_publishable_hNav9TfG49in13UfflVdUw_O-_s2-0t','Content-Type':'application/json'},body:JSON.stringify({nickname:(localStorage.getItem('atinaProgressNicknameV1')||'Visitante').trim().slice(0,40)||'Visitante',category:labels[category.value],description:text,game_area:currentContext(),screenshot:screenshotPayload})});
 const data=await response.json().catch(()=>({}));if(!response.ok||!data.success)throw Error(data.error||'Falha no envio.');
 status.textContent='Report enviado com sucesso.';description.value='';screenshot.value='';
 }catch(error){status.textContent=error.message||'Falha no envio. Tenta novamente.';}finally{send.disabled=false;}});
})();