document.addEventListener('DOMContentLoaded', () => {

  /* ====== Replace {{base_url}} placeholders with current origin ====== */

  document.body.innerHTML = document.body.innerHTML.replace(
    /\{\{base_url\}\}/g,
    window.location.origin
  );

  /* ====== Tab Switching ====== */

  const tabBtns = document.querySelectorAll('.tab-btn');
  const tabContents = {
    stable: document.getElementById('tab-stable'),
    dev: document.getElementById('tab-dev'),
  };

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      tabBtns.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      Object.values(tabContents).forEach(tc => tc.classList.remove('active'));
      const target = tabContents[btn.dataset.tab];
      if (target) target.classList.add('active');
    });
  });

  /* ====== Version Fetching ====== */

  const DL_BASE = 'dl';

  function getArchiveUrl(channel, archiveName) {
    return `${DL_BASE}/${channel}/${archiveName}`;
  }

  async function fetchText(url) {
    try {
      const res = await fetch(url, { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return (await res.text()).trim();
    } catch {
      return null;
    }
  }

  async function updateChannel(channel) {
    const versionEl = document.getElementById(`${channel}-version`);
    const downloadBtn = document.getElementById(`${channel}-download-btn`);
    const shaEl = document.getElementById(`${channel}-sha256`);

    if (!versionEl) return;

    versionEl.textContent = 'Loading...';
    if (downloadBtn) {
      downloadBtn.removeAttribute('href');
      downloadBtn.classList.add('disabled');
    }
    if (shaEl) shaEl.textContent = '\u2014';

    const version = await fetchText(`${DL_BASE}/${channel}/LATEST`);
    if (!version) {
      versionEl.textContent = 'Not available';
      return;
    }

    versionEl.textContent = `v${version}`;

    // Stable: predictable name; Dev: needs LATEST file (timestamp in filename)
    let archiveName;
    if (channel === 'stable') {
      archiveName = `homuncu-pi-${version}.tar.gz`;
    } else {
      archiveName = await fetchText(`${DL_BASE}/${channel}/LATEST`);
    }

    if (downloadBtn && archiveName) {
      downloadBtn.setAttribute('href', getArchiveUrl(channel, archiveName));
      downloadBtn.setAttribute('download', archiveName);
      downloadBtn.classList.remove('disabled');
    }

    if (shaEl && archiveName) {
      const sha = await fetchText(`${DL_BASE}/${channel}/${archiveName}.sha256`);
      if (sha) shaEl.textContent = sha;
    }
  }

  updateChannel('stable');
  updateChannel('dev');
});
