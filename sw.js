self.addEventListener('push',event=>{
 let data={title:'O ATINA tem novos desafios! 🎮',body:'Já passaram 48 horas. Volta ao ATINA e põe a mente à prova.',url:'./'};
 try{if(event.data)data={...data,...event.data.json()}}catch(_){}
 event.waitUntil(self.registration.showNotification(data.title||'ATINA',{
  body:data.body||'Está na hora de voltar a jogar!',
  icon:'./assets/atina-logo-alentejo.svg',
  badge:'./assets/atina-logo-alentejo.svg',
  tag:'atina-48h',
  data:{url:data.url||'./'},
  renotify:false
 }));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();
 const target=new URL(event.notification.data?.url||'./',self.location.origin).href;
 event.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
  for(const client of list){if(new URL(client.url).origin===self.location.origin){client.navigate(target);return client.focus()}}
  return clients.openWindow(target);
 }));
});