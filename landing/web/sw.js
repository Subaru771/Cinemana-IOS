const CACHE='cinemana-web-shell-v1';
const SHELL=['./','./index.html','./style.css','./app.mjs','./core.mjs','./manifest.webmanifest','../install-icon.png'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting()));});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('cinemana-web-shell-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',event=>{
 const request=event.request;
 if(request.method!=='GET')return;
 const url=new URL(request.url);
 // Never cache remote catalogs, media, or any private/authorization responses.
 if(url.origin!==self.location.origin)return;
 if(!url.pathname.startsWith(new URL('./',self.registration.scope).pathname))return;
 event.respondWith(caches.match(request).then(hit=>hit||fetch(request)));
});