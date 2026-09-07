(() => {
  let p = document.querySelector('div.w-full.overflow-y-auto.bg-bg-secondary');
  if (!p) {
    const f = [...document.querySelectorAll('button,div,span')]
      .find(e => (e.textContent || '').trim() === 'Forward');
    let q = f;
    for (let i = 0; i < 12 && q; i++) { if ((q.innerText || '').length > 300) { p = q; break; } q = q.parentElement; }
  }
  return JSON.stringify({ t: p ? p.innerText : 'NOPANE' });
})()
