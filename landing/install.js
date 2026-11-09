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
  const base = 'https://github.com/Subaru771/Cinemana-IOS/releases/';
  return data.signing === 'unsigned' && data.deviceTested === false &&
    typeof data.downloadURL === 'string' && data.downloadURL.startsWith(base + 'download/') &&
    /^Cinemana-iOS-.+-Unsigned\.ipa$/.test(decodeURIComponent(data.downloadURL.split('/').pop())) &&
    typeof data.releaseURL === 'string' && data.releaseURL.startsWith(base + 'tag/') &&
    /^[a-f0-9]{64}$/.test(data.sha256) && Number.isSafeInteger(data.size) && data.size > 0 &&
    [data.version, data.build, data.minOSVersion, data.date].every(v => typeof v === 'string');
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
    document.getElementById('checksum').textContent = 'SHA-256: ' + data.sha256;
    if (match && Number(match[1]) < Number(data.minOSVersion.split('.')[0])) {
      status.textContent += say(' — This build requires a newer iOS version than detected.', ' — يتطلب هذا الإصدار نسخة iOS أحدث من المكتشفة.');
      ipa.hidden = installer.hidden = true;
    }
  } catch (_) {
    status.textContent = say('Release details could not be loaded. Use GitHub releases below; no install link is enabled.', 'تعذّر تحميل تفاصيل الإصدار. استخدم إصدارات GitHub أدناه؛ لم يتم تفعيل رابط التثبيت.');
  }
}
loadRelease();
