(() => {
  const re = /^[\w.+-]+@[\w.-]+\.[a-z]{2,}$/i;
  // Primary selector (verified 2026-09-06). Falls back to a generic scan if Clay changes its markup.
  let rows = [...document.querySelectorAll('div.flex.w-full.min-w-0.flex-row.items-center.justify-between')]
    .filter(e => re.test((e.childNodes[0]?.textContent || '').trim()));
  if (rows.length === 0) {
    rows = [...document.querySelectorAll('div,li')]
      .filter(e => re.test((e.childNodes[0]?.textContent || '').trim())
                && (e.textContent || '').length < 400
                && e.querySelector('*') !== null);
  }
  return JSON.stringify(rows.map((e, i) => {
    const lab = e.closest('label') || e.parentElement;
    const t = (lab.innerText || '').split('\n').map(s => s.trim()).filter(Boolean);
    return { i, email: t[0] || '', date: t[1] || '', campaign: t[2] || '', category: t[3] || '' };
  }));
})()
