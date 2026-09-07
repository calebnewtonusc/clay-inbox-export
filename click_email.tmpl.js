(() => {
  const target='__EMAIL__';
  const re=/^[\w.+-]+@[\w.-]+\.[a-z]{2,}$/i;
  const find=()=>[...document.querySelectorAll('div.flex.w-full.min-w-0.flex-row.items-center.justify-between')]
    .filter(e=>re.test((e.childNodes[0]?.textContent||'').trim()))
    .find(e=>(e.childNodes[0]?.textContent||'').trim().toLowerCase()===target);
  let r=find();
  if(!r){
    const sc=[...document.querySelectorAll('div')].filter(d=>d.scrollHeight>d.clientHeight+200);
    for(const s of sc){ s.scrollTop=s.scrollHeight; }
    return 'SCROLLED';
  }
  const lab=r.closest('label')||r.parentElement;
  lab.scrollIntoView({block:'center'});
  lab.click();
  return 'CLICKED '+target;
})()
