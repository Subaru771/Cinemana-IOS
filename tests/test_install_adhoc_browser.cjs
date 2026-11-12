// Browser-only tests with deliberately synthetic CMS/signature fixtures. No Apple install is asserted.
const {chromium}=require('playwright');
const {execFileSync}=require('node:child_process');
const {mkdtempSync,rmSync,readFileSync}=require('node:fs');
const {tmpdir}=require('node:os');
const {join,resolve}=require('node:path');
const {createServer}=require('node:http');
const assert=require('node:assert/strict');
(async()=>{
 const folder=mkdtempSync(join(tmpdir(),'cinemana-ota-browser-'));
 let browser,server;
 try{
  execFileSync('python3',['-c',`
import importlib.util, sys
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('fixtures','tests/test_install_adhoc.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.AdHocBuilderTests.setUpClass()
t=m.AdHocBuilderTests();t.setUp()
try:
 ipa=t.create_ipa()
 m.app.build(ipa,Path(sys.argv[1])/'preview','https://example.test/private/')
 with patch.object(m.app,'verify_native'):
  m.app.build(ipa,Path(sys.argv[1])/'publish','https://example.test/private/',preview=False)
finally:
 t.doCleanups();m.AdHocBuilderTests.tearDownClass()
`,folder],{cwd:resolve(__dirname,'..')});
  server=createServer((req,res)=>{
   if(!['/preview/index.html','/publish/index.html'].includes(req.url)){res.writeHead(404);return res.end();}
   res.setHeader('Content-Type','text/html; charset=utf-8');res.end(readFileSync(join(folder,req.url)));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base='http://127.0.0.1:'+server.address().port;
  browser=await chromium.launch({headless:true,args:['--no-sandbox'],...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});
  for(const width of [320,390,768]){
   const page=await browser.newPage({viewport:{width,height:844},userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X)'});
   await page.goto(base+'/preview/index.html');
   for(const lang of ['en','ar']){
    if(lang==='ar')await page.locator('#lang').click();
    assert.equal(await page.locator('html').getAttribute('lang'),lang);
    assert.equal(await page.locator('#install').getAttribute('href'),null);
    assert.equal(await page.locator('#install').getAttribute('aria-disabled'),'true');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
   }
   await page.goto(base+'/publish/index.html');
   const link=new URL(await page.locator('#install').getAttribute('href'));
   assert.equal(link.protocol,'itms-services:');
   assert.equal(link.searchParams.get('url'),'https://example.test/private/manifest.plist');
   await page.evaluate(()=>{meta.expiry='2000-01-01T00:00:00Z';render();});
   assert.equal(await page.locator('#install').getAttribute('href'),null);
   await page.locator('#lang').click();
   assert.equal(await page.locator('#install').getAttribute('href'),null);
   await page.close();
  }
  console.log('PASS: Ad Hoc EN/AR preview disabled, mobile layouts, manifest handoff and expired-profile UI. Signatures are synthetic; native installation untested.');
 }finally{if(browser)await browser.close();if(server)await new Promise(resolve=>server.close(resolve));rmSync(folder,{recursive:true,force:true});}
})().catch(e=>{console.error(e);process.exit(1)});
