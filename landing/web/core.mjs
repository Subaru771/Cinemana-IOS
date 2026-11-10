export const API_BASE = 'https://cinemana.shabakaty.com/api/android/';
const CHILD_KEYS = new Set(['data','result','results','items','videos','video','movies','films','banner','banners','rows','content','list','episodes','episodeList','seasons','season','files','qualities','transcodedFiles','transcoddedFiles','streams','sources','videoFile','videoFiles']);
const STREAM_KEYS = ['videoUrl','videoURL','url','file','path','src','link','videoFileUrl'];
const TEXT_KEYS = ['en_title','englishTitle','enTitle','english_title','title','name'];
const get = (o,keys) => keys.map(k=>o?.[k]).find(v=>typeof v==='string' && v.trim() || typeof v==='number') ?? '';
export function safeUrl(value) {
  if(typeof value!=='string')return '';
  try {const u=new URL(value);return u.protocol==='https:' ? u.href : '';}catch{return '';}
}
export function mediaUrl(value) {
  const u=safeUrl(value);if(!u)return '';
  const pathname=new URL(u).pathname.toLowerCase();
  return /\.(jpg|jpeg|png|gif|webp|svg)$/.test(pathname)?'':u;
}
export function normalizeVideo(item,kind='') {
  if(!item || Array.isArray(item) || typeof item!=='object')return null;
  const id=String(get(item,['nb','id','videoId','video_id','videoNb','episodeId','episode_id'])).trim();
  const title=String(get(item,TEXT_KEYS)||get(item,['ar_title','arabicTitle','arTitle','arabic_title'])).trim();
  if(!id||!title)return null;
  const season=Number(get(item,['season','seasonNumber','seasonNummer','season_number']))||1;
  const episode=Number(get(item,['episodeNummer','episodeNumber','episode','episodeNb','episode_number']))||0;
  const type=String(kind||get(item,['kind','videoKind','video_kind'])||'1');
  const image=String(get(item,['imgMediumThumbObjUrl','imageThumbMediumUrl','imageMediumThumbUrl','poster','imgThumbObjUrl','imageThumbUrl','imgObjUrl','imageObjUrl','img'])||'');
  const score=Number(get(item,['stars','rating','imdbRating']));
  return {id,title,arabicTitle:String(get(item,['ar_title','arabicTitle','arTitle','arabic_title'])||''),description:String(get(item,['en_content','englishContent','description','overview','ar_content'])||''),year:String(get(item,['year'])||''),kind:type,poster:safeUrl(image),rating:score>0&&score<=10?score:null,season,episode};
}
export function extractVideos(root,kind='',limit=100) {
  const seen=new Set(),results=[];
  function visit(v,depth){if(depth>6||results.length>=limit)return;
    if(Array.isArray(v)){for(const el of v)visit(el,depth+1);}
    else if(v&&typeof v==='object'){const item=normalizeVideo(v,kind);if(item&&!seen.has(item.id)){results.push(item);seen.add(item.id);}for(const [k,child] of Object.entries(v))if(CHILD_KEYS.has(k))visit(child,depth+1);}
  }visit(root,0);return results;
}
export function extractStreams(root) {
  const seen=new Set(),found=[];
  function quality(v){const s=String(v||'').toLowerCase();if(s.includes('4k')||s.includes('2160'))return 2160;if(s.includes('1080')||s.includes('fhd'))return 1080;if(s.includes('720')||s==='hd')return 720;if(s.includes('480')||s==='sd')return 480;return 0;}
  function add(v,q){const u=mediaUrl(v);if(u&&!seen.has(u)){seen.add(u);found.push({url:u,quality:q});}}
  function visit(value,depth,q){if(depth>6||found.length>=35)return;
    if(Array.isArray(value)){value.forEach(x=>visit(x,depth+1,q));return;}
    if(typeof value==='string'){add(value,q);return;}
    if(value&&typeof value==='object'){
      const next=quality(value.resolution??value.quality??value.height??value.label??value.name)||q;
      STREAM_KEYS.forEach(k=>{if(typeof value[k]==='string')add(value[k],next);});
      for(const [k,v] of Object.entries(value)){if(CHILD_KEYS.has(k))visit(v,depth+1,next);else if(quality(k)>0&&typeof v==='string')add(v,quality(k));}
    }
  }visit(root,0,0);return found.sort((a,b)=>b.quality-a.quality);
}
export function searchPath(query,kind) {
  const data=new TextEncoder().encode(query.trim());let binary='';for(const n of data)binary+=String.fromCharCode(n);
  return 'video/V/2/videoKind/'+kind+'/itemsPerPage/20/video_title_search/'+encodeURIComponent(btoa(binary).replace(/=+$/,''));
}
export function catalogPath(kind,sort){return 'video/videoKind/'+kind+'/categoryNb/0/langNb/0/sortParam/'+sort+'/itemsPerPage/20/searchTextValue/-/pageNumber/0';}
export async function providerFetch(path,{signal}={}) {
  const response=await fetch(API_BASE+path,{mode:'cors',credentials:'omit',signal,headers:{Accept:'application/json'}});
  if(response.status===401)throw new Error('account');
  if(response.status===403||response.status===451)throw new Error('restricted');
  if(!response.ok)throw new Error('http'+response.status);
  const type=response.headers.get('content-type')||'';
  if(!type.includes('json'))throw new Error('invalid');
  return response.json();
}