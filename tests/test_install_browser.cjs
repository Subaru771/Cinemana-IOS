const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH ? {executablePath:process.env.CHROMIUM_PATH} : {}),args:['--no-sandbox']});
 for(const lang of ['en','ar']){
  for(const width of [320,390,768]){
   const context=await browser.newContext({viewport:{width,height:844},userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 Version/27.0 Mobile Safari/604.1'});
   const page=await context.newPage();
   await page.goto((process.env.INSTALL_BASE_URL || 'http://127.0.0.1:8080/')+'install'+(lang==='ar'?'-ar':'')+'.html');
   await page.locator('#ipa').waitFor({state:'visible'});
   assert.equal(await page.locator('#method').inputValue(),'modern');
   const installURL = new URL(await page.locator('#direct-install').getAttribute('href'));
   assert.equal(installURL.origin, 'https://sideinstaller.net');
   assert.equal(installURL.pathname, '/open.html');
   assert.equal(installURL.searchParams.get('url'), await page.locator('#ipa').getAttribute('href'));
   assert.equal(await page.locator('#direct-install').isVisible(), true);
   assert.equal(await page.locator('.alternative').getAttribute('open'), null);
   assert.equal(await page.locator('[data-path="modern"]').isVisible(),true);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
   await page.selectOption('#method','legacy');
   assert.equal(await page.locator('[data-path="legacy"]').isVisible(),true);
   assert.equal(await page.locator('[data-path="modern"]').isVisible(),false);
   await page.selectOption('#method','ready');
   assert.equal(await page.locator('[data-path="ready"]').isVisible(),true);
   await page.selectOption('#method','modern');
   
   await context.close();
  }
 }
 const page=await browser.newPage();
 await page.route('**/release.json',r=>r.fulfill({status:200,body:JSON.stringify({downloadURL:'https://evil.invalid/a.ipa'})}));
 await page.goto((process.env.INSTALL_BASE_URL || 'http://127.0.0.1:8080/')+'install.html');
 await page.waitForFunction(()=>document.querySelector('#release-status').textContent.includes('could not'));
 assert.equal(await page.locator('#ipa').isVisible(),false);
 assert.equal(await page.locator('#direct-install').getAttribute('href'),null);
 assert.equal(await page.locator('#method').inputValue(),'unknown');
 await page.unroute('**/release.json');
 await page.route('**/release.json',r=>r.abort());
 await page.reload();
 await page.waitForFunction(()=>document.querySelector('#release-status').textContent.includes('could not'));
 assert.equal(await page.locator('#sideinstaller').isVisible(),false);
 assert.equal(await page.locator('#direct-install').getAttribute('href'),null);
 const oldPhone = await browser.newContext({userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)'});
 const oldPage = await oldPhone.newPage();
 await oldPage.goto((process.env.INSTALL_BASE_URL || 'http://127.0.0.1:8080/')+'install.html');
 await oldPage.waitForFunction(()=>document.querySelector('#release-status').textContent.includes('newer iOS'));
 await oldPage.selectOption('#method','modern');
 assert.equal(await oldPage.locator('#direct-install').isVisible(), false);
 await oldPhone.close();
 await browser.close(); console.log('PASS: English/Arabic at 320/390/768px; RTL layout, selectors, OS hint, valid catalog, malformed and failed catalog.');
})().catch(e=>{console.error(e);process.exit(1)});
