import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeVideo,extractVideos,extractStreams,searchPath,catalogPath,safeUrl,mediaUrl} from '../landing/web/core.mjs';
test('parses catalog records and de-duplicates nested wrapper objects',()=>{
 const raw={data:{items:[{nb:11,en_title:'Movie A',kind:1,img:'https://example.org/a.jpg',stars:'7.5',year:2026},{id:'11',title:'Movie A'},{nb:12,ar_title:'مسلسل',kind:2}]}};
 const videos=extractVideos(raw);assert.equal(videos.length,2);
 assert.equal(videos[0].title,'Movie A');assert.equal(videos[1].title,'مسلسل');
 assert.equal(videos[0].rating,7.5);
});
test('extracts media URLs from supported response shapes and rejects images and unsafe URLs',()=>{
 const raw={data:{transcoddedFiles:[{resolution:'1080p',videoUrl:'https://media.example.org/high.m3u8'},{quality:'720p',url:'https://media.example.org/low.mp4'},{url:'javascript:alert(1)'},{url:'https://media.example.org/poster.jpg'}]}};
 const streams=extractStreams(raw);assert.deepEqual(streams.map(x=>x.quality),[1080,720]);
 assert.equal(mediaUrl('http://example.com/test.mp4'),'');assert.equal(safeUrl('javascript:alert(1)'),'');
 assert.equal(safeUrl('https://example.org/file'),'https://example.org/file');
});
test('generates existing native-client compatible Unicode search and catalog paths',()=>{
 assert.equal(searchPath('film',1),'video/V/2/videoKind/1/itemsPerPage/20/video_title_search/ZmlsbQ');
 assert.equal(searchPath('عربي',2),'video/V/2/videoKind/2/itemsPerPage/20/video_title_search/2LnYsdio2Yo');
 assert.equal(catalogPath(1,'views_desc'),'video/videoKind/1/categoryNb/0/langNb/0/sortParam/views_desc/itemsPerPage/20/searchTextValue/-/pageNumber/0');
});
test('rejects malformed records',()=>{
 assert.equal(normalizeVideo({nb:1}),null);assert.deepEqual(extractVideos({data:'not a record'}),[]);
});