/* ============================================================================
   R2 Shell · JS compartilhado entre todos os HTMLs do rhgpc
   ----------------------------------------------------------------------------
   Cobre:
   - Boot inicial: aplica theme/density/sidebar salvos no localStorage
   - Topbar actions: theme toggle, density toggle, sidebar collapse
   - Mobile drawer: hambúrguer + backdrop (idempotente · substitui o antigo)
   - Atalhos: Ctrl+J theme, Ctrl+K density, Ctrl+B sidebar
   ============================================================================ */

(function(){
  if (window.__r2ShellInit) return;
  window.__r2ShellInit = true;

  // ============ BOOT · aplica preferências antes do render ============
  // Roda imediatamente (não espera DOMContentLoaded) pra evitar flash.
  try {
    var html = document.documentElement;
    var theme = localStorage.getItem('r2.theme');
    var density = localStorage.getItem('r2.density');
    var sidebar = localStorage.getItem('r2.sidebar');
    if (theme === 'dark') html.setAttribute('data-theme', 'dark');
    if (density === 'compact') html.setAttribute('data-density', 'compact');
    if (sidebar === 'collapsed') html.setAttribute('data-sidebar', 'collapsed');
  } catch (e) {}

  // ============ Topbar actions + Mobile drawer (após DOM ready) ============
  function init(){
    var sb = document.querySelector('.sidebar');
    var tb = document.querySelector('.topbar');
    if (!sb || !tb) return;

    // -------- Backdrop pro mobile drawer --------
    var bd = document.querySelector('.sidebar-backdrop');
    if (!bd) {
      bd = document.createElement('div');
      bd.className = 'sidebar-backdrop';
      document.body.appendChild(bd);
    }

    function closeDrawer(){ sb.classList.remove('open'); bd.classList.remove('show'); }
    function openDrawer(){ sb.classList.add('open'); bd.classList.add('show'); }
    bd.addEventListener('click', closeDrawer);
    sb.addEventListener('click', function(e){ if (e.target.tagName === 'A') closeDrawer(); });
    document.addEventListener('keydown', function(e){ if (e.key === 'Escape') closeDrawer(); });

    // -------- Hambúrguer mobile (já pode existir do mobile drawer antigo) --------
    var hb = tb.querySelector('.mobile-hamburger');
    if (!hb) {
      hb = document.createElement('button');
      hb.className = 'mobile-hamburger';
      hb.setAttribute('aria-label', 'Abrir menu');
      hb.innerHTML = svgIcon('menu');
      tb.insertBefore(hb, tb.firstChild);
    }
    hb.addEventListener('click', function(){
      sb.classList.contains('open') ? closeDrawer() : openDrawer();
    });

    // -------- Botão de collapse sidebar (apenas desktop) --------
    var collapseBtn = document.createElement('button');
    collapseBtn.className = 'r2-sidebar-collapse-btn';
    collapseBtn.setAttribute('aria-label', 'Recolher menu');
    collapseBtn.setAttribute('title', 'Recolher menu (Ctrl+B)');
    collapseBtn.innerHTML = svgIcon('chevron-left');
    tb.insertBefore(collapseBtn, hb.nextSibling);
    collapseBtn.addEventListener('click', toggleSidebar);

    // -------- Container de ações no canto direito --------
    var actions = document.createElement('div');
    actions.className = 'r2-topbar-actions';

    // Verifica se já tem user-chip à direita pra inserir antes
    var existingChip = tb.querySelector('.user-chip, .user-info');
    var chipParent = existingChip ? existingChip.parentElement : null;

    // Theme toggle
    var themeBtn = mkBtn('theme', 'Tema escuro/claro (Ctrl+J)', toggleTheme);
    actions.appendChild(themeBtn);

    // Density toggle
    var densityBtn = mkBtn('density', 'Densidade compacta/normal (Ctrl+K)', toggleDensity);
    actions.appendChild(densityBtn);

    // Settings (placeholder · abre tooltip por enquanto)
    var settingsBtn = mkBtn('settings', 'Configurações da página', function(){
      alert('Configurações da página · feature em construção.');
    });
    actions.appendChild(settingsBtn);

    // Insere actions antes do user-chip se houver, senão no fim
    if (existingChip && chipParent === tb) {
      tb.insertBefore(actions, existingChip);
    } else {
      tb.appendChild(actions);
    }

    syncBtnStates();

    // -------- Atalhos --------
    document.addEventListener('keydown', function(e){
      if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey) {
        if (e.key === 'j' || e.key === 'J') { e.preventDefault(); toggleTheme(); }
        else if (e.key === 'k' || e.key === 'K') { e.preventDefault(); toggleDensity(); }
        else if (e.key === 'b' || e.key === 'B') { e.preventDefault(); toggleSidebar(); }
      }
    });
  }

  // ============ Helpers ============
  function mkBtn(kind, label, onClick) {
    var b = document.createElement('button');
    b.className = 'r2-icon-btn';
    b.setAttribute('aria-label', label);
    b.dataset.kind = kind;
    b.innerHTML = svgIcon(kind);
    b.addEventListener('click', onClick);
    return b;
  }

  function svgIcon(name) {
    var icons = {
      menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg>',
      'chevron-left': '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><polyline points="15 18 9 12 15 6"/></svg>',
      theme: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>',
      density: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="3" y1="15" x2="21" y2="15"/></svg>',
      settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>'
    };
    return icons[name] || '';
  }

  function syncBtnStates() {
    var html = document.documentElement;
    var isDark = html.getAttribute('data-theme') === 'dark';
    var isCompact = html.getAttribute('data-density') === 'compact';
    var themeBtn = document.querySelector('.r2-icon-btn[data-kind="theme"]');
    var densityBtn = document.querySelector('.r2-icon-btn[data-kind="density"]');
    if (themeBtn) themeBtn.dataset.active = isDark ? 'true' : 'false';
    if (densityBtn) densityBtn.dataset.active = isCompact ? 'true' : 'false';
  }

  function toggleTheme() {
    var html = document.documentElement;
    var current = html.getAttribute('data-theme');
    if (current === 'dark') {
      html.removeAttribute('data-theme');
      try { localStorage.setItem('r2.theme', 'light'); } catch(e){}
    } else {
      html.setAttribute('data-theme', 'dark');
      try { localStorage.setItem('r2.theme', 'dark'); } catch(e){}
    }
    syncBtnStates();
  }

  function toggleDensity() {
    var html = document.documentElement;
    var current = html.getAttribute('data-density');
    if (current === 'compact') {
      html.removeAttribute('data-density');
      try { localStorage.setItem('r2.density', 'normal'); } catch(e){}
    } else {
      html.setAttribute('data-density', 'compact');
      try { localStorage.setItem('r2.density', 'compact'); } catch(e){}
    }
    syncBtnStates();
  }

  function toggleSidebar() {
    var html = document.documentElement;
    var current = html.getAttribute('data-sidebar');
    if (current === 'collapsed') {
      html.removeAttribute('data-sidebar');
      try { localStorage.setItem('r2.sidebar', 'expanded'); } catch(e){}
    } else {
      html.setAttribute('data-sidebar', 'collapsed');
      try { localStorage.setItem('r2.sidebar', 'collapsed'); } catch(e){}
    }
  }

  // Expoe globals pra demos/testes
  window.r2Theme = toggleTheme;
  window.r2Density = toggleDensity;
  window.r2Sidebar = toggleSidebar;

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
