'use strict';
const arabic = document.documentElement.lang === 'ar';
const say = (en, ar) => arabic ? ar : en;
const method = document.getElementById('method');
function selectPath(value) {
  method.value = value;
  document.querySelectorAll('[data-path]').forEach(section => { section.hidden = section.dataset.path !== value; });
}
method.addEventListener('change', () => selectPath(method.value));
// iPad desktop mode and some privacy-preserving browsers conceal or freeze the OS.
// A detected version is a suggestion, never proof of compatibility.
const match = /(?:iPhone|iPad|iPod).*OS (\d+)[_\.](\d+)/.exec(navigator.userAgent);
if (match) {
  const major = Number(match[1]);
  selectPath(major >= 27 ? 'modern' : major >= 18 ? 'legacy' : major >= 16 ? 'older' : 'unknown');
  document.getElementById('device-hint').textContent = say('Browser suggests iOS ', 'يقترح المتصفح إصدار iOS ') + major + '.' + match[2] + say(' — confirm above.', ' — تأكد من الاختيار أعلاه.');
} else {
  selectPath('unknown');
}
function validRelease(data) {
  if (!data || typeof data !== 'object') return false;
  const base = 'https://github.com/Subaru771/Cinemana-IOS/releases/';
  const download = new URL(data.downloadURL);
  const release = new URL(data.releaseURL);
  return data.signing === 'unsigned' && data.deviceTested === false &&
    download.origin === 'https://github.com' && !download.search && !download.hash &&
    download.href.startsWith(base + 'download/') &&
    /^Cinemana-iOS-.+-Unsigned\.ipa$/.test(decodeURIComponent(download.pathname.split('/').pop())) &&
    release.href.startsWith(base + 'tag/') && !release.search && !release.hash &&
    /^[a-f0-9]{64}$/.test(data.sha256) && Number.isSafeInteger(data.size) && data.size > 0 && data.size <= 200000000 &&
    [data.version, data.build, data.minOSVersion].every(v => typeof v === 'string' && /^[0-9]+(?:\.[0-9]+)*$/.test(v)) &&
    typeof data.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(data.date);
}
async function loadRelease() {
  const status = document.getElementById('release-status');
  try {
    const response = await fetch('release.json', {cache: 'no-cache', signal: AbortSignal.timeout(10000)});
    if (!response.ok) throw new Error('Release unavailable');
    const data = await response.json();
    if (!validRelease(data)) throw new Error('Invalid release');
    status.textContent = say('Version ', 'الإصدار ') + data.version + ' · ' + say('build ', 'البناء ') + data.build + ' · iOS ' + data.minOSVersion + '+ · ' + (data.size / 1000000).toFixed(1) + ' MB · ' + data.date;
    const ipa = document.getElementById('ipa');
    ipa.href = data.downloadURL;
    ipa.hidden = false;
    const installer = document.getElementById('sideinstaller');
    installer.href = 'https://sideinstaller.net/open.html?url=' + encodeURIComponent(data.downloadURL);
    installer.hidden = false;
    const quick = document.getElementById('quick-install');
    quick.href = installer.href;
    quick.hidden = false;
    document.getElementById('quick-status').textContent = say('Opens SideInstaller; confirm installation in the app.', 'يفتح SideInstaller لتأكيد التثبيت داخله.');
    const direct = document.getElementById('direct-install');
    direct.href = installer.href;
    direct.hidden = false;
    document.getElementById('direct-status').textContent = say('Requires SideInstaller setup above. Confirm installation in that app.', 'يتطلب إعداد SideInstaller أعلاه. أكّد التثبيت داخل الأداة.');
    document.getElementById('checksum').textContent = 'SHA-256: ' + data.sha256;
    if (match && Number(match[1]) < Number(data.minOSVersion.split('.')[0])) {
      status.textContent += say(' — This build requires a newer iOS version than detected.', ' — يتطلب هذا الإصدار نسخة iOS أحدث من المكتشفة.');
      ipa.hidden = installer.hidden = direct.hidden = quick.hidden = true;
      document.getElementById('quick-status').textContent = say('This iOS version is below the IPA minimum.', 'إصدار iOS أقل من الحد المطلوب لملف IPA.');
      document.getElementById('direct-status').textContent = say('This iOS version is below the build minimum.', 'إصدار iOS أقل من الحد المطلوب.');
    }
  } catch (_) {
    document.getElementById('quick-status').textContent = say('Install unavailable. Check the published GitHub release.', 'التثبيت غير متاح. راجع الإصدار المنشور في GitHub.');
    document.getElementById('direct-status').textContent = say('Download unavailable. Check GitHub releases below.', 'التحميل غير متاح. راجع إصدارات GitHub أدناه.');
    status.textContent = say('Release details could not be loaded. Use GitHub releases below; no install link is enabled.', 'تعذّر تحميل تفاصيل الإصدار. استخدم إصدارات GitHub أدناه؛ لم يتم تفعيل رابط التثبيت.');
  }
}
loadRelease();
