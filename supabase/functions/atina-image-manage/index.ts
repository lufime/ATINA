import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import postgres from "npm:postgres@3.4.7";
import { createClient } from "npm:@supabase/supabase-js@2";
import JSZip from "npm:jszip@3.10.1";
const URL = Deno.env.get("SUPABASE_URL")!;
const KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DB = Deno.env.get("SUPABASE_DB_URL")!;
const BUCKET = "atina-challenge-images";
const sql = postgres(DB, { max: 1, prepare: false });
const admin = createClient(URL, KEY, { auth: { autoRefreshToken: false, persistSession: false } });
const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, apikey, x-client-info, content-type", "Access-Control-Allow-Methods":"POST, OPTIONS", "Vary":"Origin" };
const reply=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
Deno.serve(async req=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 if(req.method!=="POST") return reply({error:"Use POST."},405);
 const bearer=req.headers.get("Authorization")??"";
 const token=bearer.startsWith("Bearer ")?bearer.slice(7):"";
 if(!token) return reply({error:"Authentication required."},401);
 const {data,error}=await admin.auth.getUser(token);
 if(error||!data.user) return reply({error:"Invalid session."},401);
 const meta=data.user.app_metadata??{};
 if(!(meta.atina_admin===true||meta.role==="admin")) return reply({error:"Administrator access required."},403);
 try {
  const body=await req.json() as Record<string, any>; const action=String(body.action??"");
  const deleteChallengeRecord=async(id:number)=>{
   const result=await sql.begin(async tx=>{
    const assets=await tx`select storage_path,original_storage_path from private.atina_image_assets where challenge_id=${id}`;
    await tx`delete from private.atina_image_assets where challenge_id=${id}`;
    const deleted=await tx`delete from private.atina_challenges where challenge_id=${id} returning challenge_id`;
    if(!deleted.length) throw new Error("Desafio #"+id+" não encontrado.");
    const paths=[...new Set(assets.flatMap((a:any)=>[a.storage_path,a.original_storage_path]).filter((p:any)=>typeof p==="string"&&p.length>0))];
    return paths;
   });
   let storageWarning:string|null=null;
   if(result.length){
    const {error:storageError}=await admin.storage.from(BUCKET).remove(result);
    if(storageError) storageWarning=storageError.message;
   }
   return {challenge_id:id,storage_objects_removed:storageWarning?0:result.length,storage_warning:storageWarning};
  };
  if(action==="challenge_list"){
   const rows=await sql`select c.challenge_id,c.category,c.emoji,c.clues,c.answer,c.accepted_answers,c.active,c.difficulty,c.image_tags,c.image_description,c.solution_image_url,c.geographic_scope,c.created_at,coalesce((select json_agg(json_build_object('action',h.action,'reason',h.reason,'created_at',h.created_at) order by h.created_at desc) from private.atina_challenge_deactivation_history h where h.challenge_id=c.challenge_id),'[]'::json) as deactivation_history from private.atina_challenges c order by c.challenge_id`;
   return reply({challenges:rows});
  }
  if(action==="challenge_save"){
   const id=body.challenge_id===null||body.challenge_id===undefined||body.challenge_id===""?null:Number(body.challenge_id);
   const category=String(body.category??"").trim();
   const emoji=String(body.emoji??"").trim();
   const answer=String(body.answer??"").trim();
   const clues=Array.isArray(body.clues)?body.clues.map((x:unknown)=>String(x).trim()).filter(Boolean):[];
   let accepted=Array.isArray(body.accepted_answers)?body.accepted_answers.map((x:unknown)=>String(x).trim()).filter(Boolean):[];
   // A restrição da base de dados exige sempre um array JSON com pelo menos uma resposta.
   if(accepted.length===0 && answer) accepted=[answer];
   const difficulty=String(body.difficulty??"").trim();
   const tags=Array.isArray(body.image_tags)?body.image_tags.map((x:unknown)=>String(x).trim()).filter(Boolean):[];
   const description=body.image_description===null?null:String(body.image_description??"").trim()||null;
   const imageUrl=body.solution_image_url===null||body.solution_image_url===undefined||String(body.solution_image_url).trim()===""?null:String(body.solution_image_url).trim();
   // Guardar o URL fornecido sem validação de formato; a pré-visualização é tratada no formulário.
   if(!category||!emoji||!answer) return reply({error:"Preenche categoria, emoji e solução."},400);
   if(id===null && ![5,6].includes(clues.length)) return reply({error:"Um novo desafio tem de ter exatamente 5 ou 6 pistas."},400);
   if(!["easy","medium","hard"].includes(difficulty)) return reply({error:"Dificuldade inválida."},400);
   if(id!==null&&(!Number.isSafeInteger(id)||id<0)) return reply({error:"ID inválido."},400);
   const active=body.active!==false;
   const deactivationReason=String(body.deactivation_reason??"").trim();
   if(id===null){
    if(!active&&!deactivationReason) return reply({error:"Indica o motivo obrigatório da desactivação."},400);
    const result=await sql.begin(async tx=>{
     const next=await tx`select coalesce(max(challenge_id),-1)+1 as id from private.atina_challenges`;
     const newId=Number(next[0].id);
     await tx`insert into private.atina_challenges(challenge_id,category,emoji,clues,answer,accepted_answers,active,difficulty,image_tags,image_description,solution_image_url) values(${newId},${category},${emoji},${JSON.stringify(clues)}::jsonb,${answer},${JSON.stringify(accepted)}::jsonb,${active},${difficulty},${tags},${description},${imageUrl})`;
     if(!active) await tx`insert into private.atina_challenge_deactivation_history(challenge_id,action,reason,admin_user_id) values(${newId},'deactivated',${deactivationReason},${data.user.id})`;
     return newId;
    });
    return reply({success:true,created:true,challenge_id:result});
   }
   const result=await sql.begin(async tx=>{
    const current=await tx`select active from private.atina_challenges where challenge_id=${id} for update`;
    if(!current.length) return null;
    const wasActive=current[0].active===true;
    if(wasActive&&!active&&!deactivationReason) throw new Error("Indica o motivo obrigatório da desactivação.");
    await tx`update private.atina_challenges set category=${category},emoji=${emoji},answer=${answer},active=${active},difficulty=${difficulty},image_tags=${tags},image_description=${description},solution_image_url=${imageUrl} where challenge_id=${id}`;
    if(wasActive&&!active) await tx`insert into private.atina_challenge_deactivation_history(challenge_id,action,reason,admin_user_id) values(${id},'deactivated',${deactivationReason},${data.user.id})`;
    if(!wasActive&&active) await tx`insert into private.atina_challenge_deactivation_history(challenge_id,action,reason,admin_user_id) values(${id},'reactivated',null,${data.user.id})`;
    return id;
   });
   if(result===null) return reply({error:"Desafio não encontrado."},404);
   return reply({success:true,updated:true,challenge_id:id});
  }
  if(action==="challenge_delete"){
   const id=Number(body.challenge_id);
   if(!Number.isSafeInteger(id)||id<0) return reply({error:"ID inválido."},400);
   const result=await deleteChallengeRecord(id);
   return reply({success:true,deleted:true,...result});
  }
  if(action==="challenge_delete_many"){
   const ids:number[]=Array.isArray(body.challenge_ids)?[...new Set<number>((body.challenge_ids as unknown[]).map((x:unknown)=>Number(x)))]:[];
   if(!ids.length||ids.length>2000||ids.some((id:number)=>!Number.isSafeInteger(id)||id<0)) return reply({error:"Indica entre 1 e 2000 IDs válidos."},400);
   const deleted:any[]=[],failed:any[]=[];
   for(const id of ids){try{deleted.push(await deleteChallengeRecord(id));}catch(e){failed.push({challenge_id:id,error:e instanceof Error?e.message:"Falha ao apagar."});}}
   return reply({success:failed.length===0,deleted_count:deleted.length,failed_count:failed.length,deleted,failed});
  }
  if(action==="challenge_toggle"){
   const id=Number(body.challenge_id),active=body.active===true,reason=String(body.reason??"").trim();
   if(!Number.isSafeInteger(id)||id<0) return reply({error:"ID inválido."},400);
   const row=await sql.begin(async tx=>{
    const current=await tx`select active from private.atina_challenges where challenge_id=${id} for update`;
    if(!current.length) return null;
    const wasActive=current[0].active===true;
    if(wasActive&&!active&&!reason) throw new Error("Indica o motivo obrigatório da desactivação.");
    await tx`update private.atina_challenges set active=${active} where challenge_id=${id}`;
    if(wasActive&&!active) await tx`insert into private.atina_challenge_deactivation_history(challenge_id,action,reason,admin_user_id) values(${id},'deactivated',${reason},${data.user.id})`;
    if(!wasActive&&active) await tx`insert into private.atina_challenge_deactivation_history(challenge_id,action,reason,admin_user_id) values(${id},'reactivated',null,${data.user.id})`;
    return {challenge_id:id,active};
   });
   if(!row) return reply({error:"Desafio não encontrado."},404);
   return reply({success:true,...row});
  }
  if(action==="players"){
   const rows=await sql`select p.id,p.nickname,p.xp,p.total_challenges,p.current_streak,p.last_played_date,p.created_at,p.updated_at,(select max(e.created_at) from private.atina_v2_progress_events e where e.player_id=p.id) as last_activity from private.atina_v2_players p order by p.updated_at desc limit 500`;
   const accounts=await sql`select player_id,nickname,created_at from private.atina_player_accounts order by created_at desc`;
   const accountMap=new Map(accounts.map(a=>[a.player_id,{nickname:a.nickname,created_at:a.created_at}]));
   return reply({players:rows.map(p=>({...p,account:accountMap.get(p.id)??null}))});
  }
  if(action==="presence"){
   const rows=await sql`select session_id,coalesce(nullif(nickname,''),'Visitante') as nickname,last_seen_at, (last_seen_at > now()-interval '2 minutes') as online from private.atina_site_presence where last_seen_at > now()-interval '30 days' order by last_seen_at desc limit 200`;
   return reply({players:rows});
  }
  if(action==="dashboard"){
   const total=await sql`select count(*)::int as n from private.atina_challenges`;
   const published=await sql`select count(*)::int as n from private.atina_image_assets where status='published'`;
   const pending=await sql`select count(*)::int as n from private.atina_image_assets where status='pending'`;
   const approved=await sql`select count(*)::int as n from private.atina_image_assets where status='approved'`;
   const broken=await sql`select count(*)::int as n from private.atina_image_assets where status='broken'`;
   const missing=await sql`select count(*)::int as n from private.atina_challenges where solution_image_url is null or btrim(solution_image_url)=''`;
   return reply({stats:{total_challenges:total[0].n,published:published[0].n,pending:pending[0].n,approved:approved[0].n,broken:broken[0].n,missing_images:missing[0].n}});
  }
  if(action==="list"){
   const rows=await sql`select a.challenge_id,a.image_url,a.storage_path,a.source,a.source_url,a.author,a.license,a.license_url,a.attribution,a.mime_type,a.file_size_bytes,a.status,a.verification_notes,a.watermark_applied,a.original_storage_path,a.created_at,c.image_url as game_image_url,c.solution_image_url,c.answer as solution from private.atina_image_assets a join private.atina_challenges c using(challenge_id) order by a.challenge_id`;
   return reply({assets:rows});
  }
  if(action==="download_zip"){
   const requested:Record<string, unknown>[]=Array.isArray(body.items)?body.items.filter((x:unknown):x is Record<string, unknown>=>!!x&&typeof x==="object"&&!Array.isArray(x)):[];
   const unique:Record<string, unknown>[]=[...new Map<string,Record<string, unknown>>(requested.map((x)=>[String(x.id),x])).values()];
   if(!unique.length||unique.length>100) return reply({error:"Indica entre 1 e 100 imagens."},400);
   const zip=new JSZip(); let count=0; const errors:string[]=[];
   for(const item of unique){
    const id=Number(item?.id);
    if(!Number.isSafeInteger(id)||id<0){errors.push("ID inválido");continue}
    const rows=await sql`select coalesce(original_storage_path,storage_path) as storage_path,coalesce(original_mime_type,mime_type) as mime_type from private.atina_image_assets where challenge_id=${id} limit 1`;
    if(!rows.length||!rows[0].storage_path){errors.push("ID "+id+": sem ficheiro original");continue}
    const {data:file,error:fileError}=await admin.storage.from(BUCKET).download(rows[0].storage_path);
    if(fileError||!file){errors.push("ID "+id+": "+(fileError?.message??"ficheiro vazio"));continue}
    const supplied=String(item?.filename??"").replace(/[\\\\/\\r\\n"]/g,"_").slice(0,160);
    const ext=rows[0].mime_type==="image/png"?"png":rows[0].mime_type==="image/jpeg"?"jpg":"webp";
    const filename=supplied ? supplied.replace(/\\.[^.]+$/, "")+"."+ext : ("atina-"+id+"."+ext);
    zip.file(filename,await file.arrayBuffer()); count++;
   }
   if(!count) return reply({error:"Não foi possível obter nenhum original.",details:errors},502);
   const archive=await zip.generateAsync({type:"uint8array",compression:"STORE"});
   return new Response(archive.buffer.slice(archive.byteOffset,archive.byteOffset+archive.byteLength) as ArrayBuffer,{status:200,headers:{...cors,"Content-Type":"application/zip","Content-Length":String(archive.byteLength),"Content-Disposition":'attachment; filename="ATINA_IMAGENS_ORIGINAIS.zip"',"X-Images-Included":String(count),"X-Images-Failed":String(errors.length),"Cache-Control":"no-store"}});
  }
  const id=Number(body.challenge_id);
  if(!Number.isSafeInteger(id)||id<0) return reply({error:"Invalid challenge_id."},400);
  const rows=await sql`select a.*,c.solution_image_url from private.atina_image_assets a join private.atina_challenges c using(challenge_id) where a.challenge_id=${id} limit 1`;
  if(!rows.length) return reply({error:"Image record not found."},404);
  const asset=rows[0];
  if(action==="download"){
   const originalPath=asset.original_storage_path || asset.storage_path;
   if(!originalPath) return reply({error:"O registo não tem caminho de armazenamento."},404);
   const inferredMime=originalPath.toLowerCase().endsWith(".png")?"image/png":originalPath.toLowerCase().endsWith(".jpg")||originalPath.toLowerCase().endsWith(".jpeg")?"image/jpeg":originalPath.toLowerCase().endsWith(".webp")?"image/webp":null;
   const originalMime=asset.original_mime_type || inferredMime || asset.mime_type || "application/octet-stream";
   const {data:file,error:fileError}=await admin.storage.from(BUCKET).download(originalPath);
   if(fileError||!file) return reply({error:"Não foi possível obter o ficheiro original.",detail:fileError?.message??"Ficheiro vazio."},502);
   const requested=String(body.filename??"").replace(/[\\/\\r\\n"]/g,"_").slice(0,160);
   const ext=originalMime==="image/png"?"png":originalMime==="image/jpeg"?"jpg":originalMime==="image/webp"?"webp":"img";
   const filename=requested ? requested.replace(/\\.[^.]+$/, "")+"."+ext : (`atina-${id}.${ext}`);
   return new Response(file,{status:200,headers:{...cors,"Content-Type":originalMime==="application/octet-stream"?(file.type||originalMime):originalMime,"Content-Length":String(file.size),"Content-Disposition":`attachment; filename="${filename}"`,"Cache-Control":"no-store"}});
  }
  if(action==="approve"){
   await sql`update private.atina_image_assets set status='approved',verified_at=now(),verification_notes='Approved by administrator.',updated_at=now() where challenge_id=${id}`;
   return reply({success:true,status:"approved"});
  }
  if(action==="publish"){
   if(asset.status!=="approved") return reply({error:"Confirma primeiro a imagem antes de a publicar."},409);
   if(!asset.image_url) return reply({error:"Imagem sem URL válida."},400);
   await sql`update private.atina_challenges set solution_image_url=${asset.image_url} where challenge_id=${id}`;
   await sql`update private.atina_image_assets set status='published',verified_at=coalesce(verified_at,now()),verification_notes='Published to the game by administrator.',updated_at=now() where challenge_id=${id}`;
   return reply({success:true,published:true,status:"published",image_url:asset.image_url});
  }
  if(action==="delete"){
   const paths=[...new Set([asset.storage_path,asset.original_storage_path].filter((p):p is string=>typeof p==="string"&&p.length>0))];
   if(paths.length){
    const {error:removeError}=await admin.storage.from(BUCKET).remove(paths);
    if(removeError) return reply({error:"Could not delete all storage objects.",detail:removeError.message,paths},502);
   }
   await sql`update private.atina_challenges set image_url=case when image_url=${asset.image_url} then null else image_url end, solution_image_url=case when solution_image_url=${asset.image_url} then null else solution_image_url end where challenge_id=${id}`;
   await sql`delete from private.atina_image_assets where challenge_id=${id}`;
   return reply({success:true,deleted:true,storage_objects_removed:paths.length});
  }
  return reply({error:"Unknown action."},400);
 } catch(e) { return reply({error:e instanceof Error?e.message:"Request failed."},500); }
});