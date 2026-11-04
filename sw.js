const CACHE='au-gestion-v2';
const FILES=['./','./manifest.webmanifest','./icon.svg'];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(FILES)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  const request=event.request;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin || request.method!=='GET') return;

  // HTML siempre se valida primero en red para que las correcciones lleguen al iPhone.
  if(request.mode==='navigate' || url.pathname.endsWith('/index.html') || url.pathname.endsWith('/supabase-config.js')){
    event.respondWith(
      fetch(request,{cache:'no-store'}).then(response=>{
        if(response.ok && request.mode!=='navigate'){
          const copy=response.clone();
          caches.open(CACHE).then(cache=>cache.put(request,copy));
        }
        return response;
      }).catch(()=>caches.match(request).then(cached=>cached||caches.match('./')))
    );
    return;
  }

  event.respondWith(caches.match(request).then(cached=>cached||fetch(request)));
});
