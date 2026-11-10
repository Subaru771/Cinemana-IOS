import {extractVideos,extractStreams,searchPath,catalogPath,providerFetch,safeUrl,mediaUrl} from './core.mjs';
const $=id=>document.getElementById(id);
const STR={
 en:{overline:'Made for your iPhone',headline:'Your cinema. <em>Anywhere.</em>',subtitle:'No IPA, computer, or signing certificate. Add Cinemana Web to your Home Screen from Safari.',addHome:'How to add to Home Screen',home:'Home',movies:'Movies',series:'Series',saved:'Saved',footer:'Independent web beta. Provider access and playback depend on your network and its permissions. Downloads are not supported here.',playLink:'Play your own media link',privacy:'Privacy',play:'Play',save:'Save',unsave:'Saved ✓',installTitle:'Install Cinemana Web',install1:'Open this page in Safari on your iPhone.',install2:'Tap Share, then Add to Home Screen.',install3:'Enable Open as Web App and tap Add.',installNote:'The icon will open Cinemana Web without Safari’s tabs. No Apple ID sign-in is needed.',restrictionNote:'The web app cannot bypass provider network restrictions or Safari’s media permissions.',linkTitle:'Play a media URL',linkNote:'Paste an HTTPS MP4 or HLS link you have permission to play. This does not bypass DRM or provider restrictions.',discover:'Discover',empty:'Nothing to display',emptyDetail:'Try refreshing or searching for a title.',search:'Search movies and series',loading:'Loading catalog…',failed:'The Cinemana provider could not be reached from this browser. It may restrict your network or block browser access (CORS). The app is installed, but catalog and provider playback need an authorized browser-accessible API.',partial:'Some catalog sections could not be loaded. Results may be incomplete.',searchFailed:'Search is unavailable from this browser or network.',mediaFailed:'No browser-playable video source was returned. The source may be restricted or incompatible with Safari.',mediaError:'Safari could not play this stream. Check format, network permission, and server access.',invalidUrl:'Enter a valid HTTPS media URL.',episodes:'Episodes',episodesFail:'Episodes could not be loaded for this title.',loadingEpisode:'Loading episodes…',noEpisodes:'No episodes were returned.',item:'titles',offline:'Offline — your saved titles are available locally, but videos and catalog require a connection.'},
 ar:{overline:'مخصص للآيفون',headline:'سينمانا. <em>على شاشتك.</em>',subtitle:'بدون IPA أو كمبيوتر أو شهادات توقيع. أضف سينمانا ويب إلى الشاشة الرئيسية من Safari.',addHome:'طريقة الإضافة للشاشة الرئيسية',home:'الرئيسية',movies:'أفلام',series:'مسلسلات',saved:'المحفوظة',footer:'نسخة ويب تجريبية مستقلة. يتوقف الوصول والتشغيل على الشبكة وصلاحيات المصدر. التنزيل غير متاح هنا.',playLink:'تشغيل رابط فيديو خاص بك',privacy:'الخصوصية',play:'تشغيل',save:'حفظ',unsave:'محفوظ ✓',installTitle:'تثبيت سينمانا ويب',install1:'افتح هذه الصفحة باستخدام Safari على الآيفون.',install2:'اضغط مشاركة ثم إضافة إلى الشاشة الرئيسية.',install3:'فعّل فتح كتطبيق ويب ثم اضغط إضافة.',installNote:'سيفتح رمز سينمانا كتطبيق دون تبويبات Safari. لا يلزم تسجيل دخول Apple.',restrictionNote:'لا يمكن لتطبيق الويب تجاوز قيود الشبكة الخاصة بالمصدر أو صلاحيات تشغيل Safari.',linkTitle:'تشغيل رابط فيديو',linkNote:'الصق رابط HTTPS لملف MP4 أو HLS مصرح لك بتشغيله. لا يتجاوز حماية المحتوى أو قيود المصدر.',discover:'اكتشف',empty:'لا توجد نتائج',emptyDetail:'جرّب التحديث أو البحث عن عنوان.',search:'ابحث عن الأفلام والمسلسلات',loading:'جار تحميل المحتوى…',failed:'تعذّر الاتصال بخدمة سينمانا عبر المتصفح. قد تكون الشبكة مقيدة أو يمنع المصدر اتصال المتصفح (CORS). يبقى تطبيق الويب مثبتاً، لكن المحتوى والتشغيل يتطلبان واجهة مرخصة للمتصفح.',partial:'تعذر تحميل بعض الأقسام. قد تكون النتائج ناقصة.',searchFailed:'البحث غير متاح عبر هذا المتصفح أو الشبكة.',mediaFailed:'لم يعط المصدر رابط فيديو قابلاً للتشغيل في Safari.',mediaError:'تعذّر تشغيل الفيديو في Safari. تأكد من الصيغة والشبكة وصلاحية المصدر.',invalidUrl:'أدخل رابط HTTPS صحيحاً.',episodes:'الحلقات',episodesFail:'تعذر تحميل حلقات هذا المسلسل.',loadingEpisode:'جار تحميل الحلقات…',noEpisodes:'لم يتم العثور على حلقات.',item:'عنوان',offline:'غير متصل بالإنترنت — المحفوظات متاحة محلياً، لكن الفيديو والمحتوى يحتاجان إلى اتصال.'}
};
let lang=localStorage.getItem('cinemana-web-lang')==='ar'?'ar':'en';
let tab='home',items=[],selected=null,searchRequest=0,searchTimer=null;
const KEY='cinemana-web-saved-v1';
function loadSaved(){try {const v=JSON.parse(localStorage.getItem(KEY)||'[]');return Array.isArray(v)?v.filter(x=>x&&typeof x.id==='string'&&typeof x.title==='string').slice(0,300):[];}catch{return [];}}
let saved=loadSaved();
const t=k=>STR[lang][k]||k;
function translate() {
 document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';
 $('language').textContent=lang==='ar'?'English':'عربي';
 document.querySelectorAll('[data-i18n]').forEach(el=>{
  const key=el.dataset.i18n;
  if(key==='headline'){el.replaceChildren(document.createTextNode(lang==='ar'?'سينمانا. ':'Your cinema. '));const em=document.createElement('em');em.textContent=lang==='ar'?'على شاشتك.':'Anywhere.';el.append(em);}
  else el.textContent=t(key);
 });
 $('search').placeholder=t('search');
 $('search').setAttribute('aria-label',t('search'));
 render();
}
function notice(msg){$('notice').textContent=msg;$('notice').hidden=!msg;}
function announceEmpty(title,detail){$('empty').hidden=false;$('empty-title').textContent=title;$('empty-detail').textContent=detail;}
function openModal(id){const el=$(id);if(!el.open)el.showModal();}
function closeModal(id){const el=$(id);if(el.open)el.close();}
function savedTitle(video){return saved.some(x=>x.id===video.id);}
function saveTitle(video){saved=savedTitle(video)?saved.filter(x=>x.id!==video.id):[video,...saved].slice(0,300);try{localStorage.setItem(KEY,JSON.stringify(saved));}catch{notice('Local storage is unavailable. Saved titles may not persist.');}render();if(selected)$('toggle-save').textContent=savedTitle(selected)?t('unsave'):t('save');}
function tile(video) {
 const button=document.createElement('button');button.type='button';button.className='tile';button.setAttribute('aria-label',video.title);button.addEventListener('click',()=>showDetails(video));
 const frame=document.createElement('div');frame.className='tile-image';
 if(video.poster){const img=document.createElement('img');img.src=video.poster;img.alt='';img.loading='lazy';img.decoding='async';img.addEventListener('error',()=>{img.remove();const fallback=document.createElement('span');fallback.className='placeholder';fallback.textContent='▶';frame.append(fallback);},{once:true});frame.append(img);}
 else{const placeholder=document.createElement('span');placeholder.className='placeholder';placeholder.textContent='▶';frame.append(placeholder);}
 const badge=document.createElement('span');badge.className='tile-tag';badge.textContent=video.kind==='2'?t('series'):t('movies');frame.append(badge);
 const info=document.createElement('div');info.className='tile-info';const title=document.createElement('div');title.className='tile-title';title.textContent=lang==='ar'&&video.arabicTitle?video.arabicTitle:video.title;
 const meta=document.createElement('div');meta.className='tile-meta';meta.textContent=[video.year,video.rating?'★ '+video.rating:''].filter(Boolean).join(' · ');
 info.append(title,meta);button.append(frame,info);return button;
}
function viewItems(){let list=tab==='saved'?saved:items;
 if(tab==='movies')list=list.filter(x=>x.kind!=='2');
 if(tab==='series')list=list.filter(x=>x.kind==='2');
 const query=$('search').value.trim().toLocaleLowerCase();
 if(query)list=list.filter(x=>(x.title+' '+x.arabicTitle).toLocaleLowerCase().includes(query));
 return list;
}
function render(){
 document.querySelectorAll('[data-tab]').forEach(b=>{const active=b.dataset.tab===tab;b.classList.toggle('active',active);if(active)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');});
 $('list-heading').textContent=tab==='home'?t('discover'):t(tab);
 const results=viewItems();$('result-count').textContent=results.length?' '+results.length+' '+t('item'):'';
 $('catalog').replaceChildren(...results.map(tile));
 $('empty').hidden=!!results.length;
 if(!results.length)announceEmpty(t('empty'),t('emptyDetail'));
}
function setTab(next){tab=next;render();}
async function loadCatalog(){
 if(!navigator.onLine){notice(t('offline'));render();return;}
 notice(t('loading'));$('refresh').disabled=true;
 const outcomes=await Promise.allSettled([1,2].flatMap(kind=>['views_desc','desc'].map(sort=>providerFetch(catalogPath(kind,sort)).then(data=>extractVideos(data,String(kind),40)))));
 let success=0;const byId=new Map();
 for(const outcome of outcomes){if(outcome.status==='fulfilled'){success++;for(const video of outcome.value){const id=video.kind+':'+video.id;if(!byId.has(id))byId.set(id,video);}}}
 items=[...byId.values()];$('refresh').disabled=false;
 notice(success===0?t('failed'):success<outcomes.length?t('partial'):'');render();
}
async function remoteSearch(query){
 if(!query.trim()){await loadCatalog();return;}
 const request=++searchRequest;
 notice(t('loading'));
 const searches=await Promise.allSettled([1,2].map(kind=>providerFetch(searchPath(query,kind)).then(data=>extractVideos(data,String(kind),60))));
 if(request!==searchRequest)return;
 let good=0;const found=new Map();
 for(const result of searches){if(result.status==='fulfilled'){good++;for(const v of result.value)found.set(v.kind+':'+v.id,v);}}
 if(good){items=[...found.values()];notice(good===2?'':t('partial'));}
 else{items=[];notice(t('searchFailed'));}
 render();
}
async function showDetails(video){
 selected=video;
 $('detail-name').textContent=lang==='ar'&&video.arabicTitle?video.arabicTitle:video.title;
 $('detail-type').textContent=video.kind==='2'?t('series'):t('movies');
 $('detail-meta').textContent=[video.year,video.rating?'★ '+video.rating:''].filter(Boolean).join(' · ');
 $('detail-summary').textContent=video.description||'';
 $('detail-error').textContent='';
 $('toggle-save').textContent=savedTitle(video)?t('unsave'):t('save');
 const poster=$('detail-poster');poster.hidden=!video.poster;poster.src=video.poster||'';
 $('episodes').hidden=true;$('episodes').replaceChildren();
 openModal('details');
 if(video.kind==='2') {
  const container=$('episodes');container.hidden=false;container.textContent=t('loadingEpisode');
  try{
   const raw=await providerFetch('videoSeason/id/'+encodeURIComponent(video.id));
   if(selected?.id!==video.id)return;
   const eps=extractVideos(raw,'2',300).filter(x=>x.id!==video.id&&x.episode>0).sort((a,b)=>a.season-b.season||a.episode-b.episode);
   container.replaceChildren();
   if(!eps.length){container.textContent=t('noEpisodes');return;}
   const title=document.createElement('h3');title.textContent=t('episodes');container.append(title);
   eps.forEach(ep=>{const b=document.createElement('button');b.type='button';b.textContent='S'+ep.season+' · E'+ep.episode+' — '+ep.title;b.addEventListener('click',()=>playTitle(ep));container.append(b);});
  }catch{container.textContent=t('episodesFail');}
 }
}
async function playTitle(video) {
 $('detail-error').textContent='';
 $('play').disabled=true;
 try{
  const paths=['transcoddedfiles/id/'+encodeURIComponent(video.id),'allVideoInfo/id/'+encodeURIComponent(video.id)];
  const responses=await Promise.allSettled(paths.map(path=>providerFetch(path)));
  const streams=responses.filter(x=>x.status==='fulfilled').flatMap(x=>extractStreams(x.value));
  const unique=[...new Map(streams.map(s=>[s.url,s])).values()].sort((a,b)=>b.quality-a.quality);
  if(!unique.length)throw new Error(t('mediaFailed'));
  closeModal('details');playMedia(unique[0].url,video.title);
 }catch(e){$('detail-error').textContent=e.message===t('mediaFailed')?e.message:t('mediaFailed');}
 finally{$('play').disabled=false;}
}
function playMedia(url,title){
 if(!mediaUrl(url)){const target=$('link-dialog').open?'link-error':'detail-error';$(target).textContent=t('invalidUrl');return;}
 const video=$('video');video.pause();video.removeAttribute('src');video.load();
 $('player-title').textContent=title||'Cinemana';$('player-error').textContent='';
 video.src=url;openModal('player-dialog');video.load();
 // iOS requires a user gesture for playback; the native controls remain visible.
}
document.querySelectorAll('[data-close]').forEach(b=>b.addEventListener('click',()=>closeModal(b.dataset.close)));
$('player-dialog').addEventListener('close',()=>{const v=$('video');v.pause();v.removeAttribute('src');v.load();});
$('video').addEventListener('error',()=>$('player-error').textContent=t('mediaError'));
$('language').addEventListener('click',()=>{lang=lang==='en'?'ar':'en';localStorage.setItem('cinemana-web-lang',lang);translate();});
$('help').addEventListener('click',()=>openModal('install-dialog'));
$('install-instructions').addEventListener('click',()=>openModal('install-dialog'));
$('open-link').addEventListener('click',()=>{$('link-error').textContent='';openModal('link-dialog');});
$('play-link').addEventListener('click',()=>{
 const url=safeUrl($('media-url').value.trim());
 if(!mediaUrl(url)){$('link-error').textContent=t('invalidUrl');return;}
 closeModal('link-dialog');playMedia(url,'Media link');
});
$('refresh').addEventListener('click',()=>{$('search').value='';searchRequest++;loadCatalog();});
$('toggle-save').addEventListener('click',()=>{if(selected)saveTitle(selected);});
$('play').addEventListener('click',()=>{if(selected)playTitle(selected);});
document.querySelectorAll('[data-tab]').forEach(b=>b.addEventListener('click',()=>setTab(b.dataset.tab)));
$('search').addEventListener('input',()=>{clearTimeout(searchTimer);if(tab==='saved'){render();return;}searchTimer=setTimeout(()=>{if(!$('search').value.trim())loadCatalog();else remoteSearch($('search').value.trim());},400);});
window.addEventListener('online',()=>{if(!items.length)loadCatalog();});
window.addEventListener('offline',()=>notice(t('offline')));
if('serviceWorker'in navigator)window.addEventListener('load',()=>navigator.serviceWorker.register('./sw.js').catch(()=>{}));
translate();loadCatalog();