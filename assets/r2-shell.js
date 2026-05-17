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

    // Search (Cmd+K)
    var searchBtn = mkBtn('search', 'Buscar (Cmd+K ou /)', function(){ openSearch(); });
    actions.appendChild(searchBtn);

    // Bell (notificações) com dropdown
    var bellBtn = mkBtn('bell', 'Notificações', function(e){
      e.stopPropagation();
      toggleNotifications(bellBtn);
    });
    var badge = document.createElement('span');
    badge.className = 'r2-bell-badge';
    badge.textContent = '3';
    bellBtn.appendChild(badge);
    actions.appendChild(bellBtn);

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
      // Torna user-chip clicavel para abrir dropdown
      attachUserDropdown(existingChip);
    } else {
      tb.appendChild(actions);
    }

    syncBtnStates();

    // -------- Atalhos --------
    document.addEventListener('keydown', function(e){
      if ((e.ctrlKey || e.metaKey) && !e.altKey && !e.shiftKey) {
        if (e.key === 'j' || e.key === 'J') { e.preventDefault(); toggleTheme(); }
        else if (e.key === 'k' || e.key === 'K') {
          // Cmd+K abre search · Cmd+Shift+K toggle density (precedência search)
          if (e.shiftKey) { e.preventDefault(); toggleDensity(); }
          else { e.preventDefault(); openSearch(); }
        }
        else if (e.key === 'b' || e.key === 'B') { e.preventDefault(); toggleSidebar(); }
      }
      if (e.key === '/' && !isInputFocused()) { e.preventDefault(); openSearch(); }
    });
  }

  function isInputFocused() {
    var el = document.activeElement;
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  }

  // ============ User Dropdown ============
  function attachUserDropdown(chip) {
    chip.classList.add('r2-user-chip-trigger');
    chip.style.cursor = 'pointer';
    chip.addEventListener('click', function(e){
      e.stopPropagation();
      toggleUserDropdown(chip);
    });
  }

  function toggleUserDropdown(anchor) {
    var existing = document.querySelector('.r2-user-dropdown');
    if (existing) { existing.remove(); return; }

    // Extrai nome/role do user-chip se possivel
    var nameEl = anchor.querySelector('.user-name, .user-info > :first-child');
    var roleEl = anchor.querySelector('.user-role, .user-info > :last-child');
    var avatarEl = anchor.querySelector('.user-avatar-tb, [class*="avatar"]');

    var name = nameEl ? nameEl.textContent.trim() : 'Usuário';
    var role = roleEl ? roleEl.textContent.trim() : '';
    var initials = avatarEl ? avatarEl.textContent.trim() : name.split(' ').map(function(s){return s[0];}).slice(0,2).join('');
    var email = (name.toLowerCase().replace(/[^a-z]/g, '.') + '@gpc.com.br').replace(/\.+/g, '.');

    // Detectar role atual (super_admin/diretoria/rh/lider/colaborador)
    var roleMatch = (role.toLowerCase().match(/super_admin|diretoria|rh|lider|colaborador/) || ['colaborador'])[0];

    var dd = document.createElement('div');
    dd.className = 'r2-user-dropdown';
    dd.innerHTML =
      '<div class="r2-user-dd-head">' +
        '<div class="r2-user-dd-avatar">' + initials + '</div>' +
        '<div class="r2-user-dd-info">' +
          '<div class="r2-user-dd-name">' + name + '</div>' +
          '<div class="r2-user-dd-email">' + email + '</div>' +
        '</div>' +
      '</div>' +
      '<div class="r2-user-dd-list">' +
        '<a class="r2-user-dd-item" href="r2_people_minha_trajetoria.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>Minha trajetória<span class="r2-user-dd-role-pill">' + roleMatch + '</span></a>' +
        '<a class="r2-user-dd-item" href="r2_people_colaborador.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>Editar ficha</a>' +
        '<a class="r2-user-dd-item" href="r2_people_notificacoes.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/></svg>Notificações</a>' +
        '<div class="r2-user-dd-divider"></div>' +
        '<a class="r2-user-dd-item" href="r2_people_configuracoes.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>Preferências</a>' +
        '<button class="r2-user-dd-item" onclick="r2Theme()"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>Alternar tema<span style="margin-left:auto;font-family:JetBrains Mono,monospace;font-size:9.5px;color:var(--txt3);">⌘J</span></button>' +
        '<a class="r2-user-dd-item" href="r2_people_login.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/></svg>Trocar de tenant</a>' +
        '<div class="r2-user-dd-divider"></div>' +
        '<a class="r2-user-dd-item danger" href="r2_people_login.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>Sair</a>' +
      '</div>';
    document.body.appendChild(dd);

    // Posicionar abaixo do user-chip alinhado a direita
    var r = anchor.getBoundingClientRect();
    dd.style.top = (r.bottom + 6) + 'px';
    dd.style.right = (window.innerWidth - r.right) + 'px';

    // Click fora fecha
    setTimeout(function(){
      document.addEventListener('click', function closeOnOutside(e){
        if (!dd.contains(e.target) && !anchor.contains(e.target)) {
          dd.remove();
          document.removeEventListener('click', closeOnOutside);
        }
      });
    }, 10);
  }

  // ============ Search overlay (Cmd+K) ============
  // Indice global de paginas · usado pra busca rapida
  var SEARCH_INDEX = [
    { title: 'Início', url: 'r2_people_home.html', cat: 'Home', icon: '🏠', kw: 'home dashboard inicio' },
    { title: 'Minha jornada', url: 'r2_people_minha_trajetoria.html', cat: 'Você', icon: '📊', kw: 'trajetoria perfil eu' },
    { title: 'Notificações', url: 'r2_people_notificacoes.html', cat: 'Você', icon: '🔔', kw: 'alertas avisos' },
    { title: 'Comunicados internos', url: 'r2_people_comunicados.html', cat: 'Comunicação', icon: '📢', kw: 'mural feed posts noticia' },
    { title: 'Feedback e mural', url: 'r2_people_feedback_mural.html', cat: 'Comunicação', icon: '👏', kw: 'reconhecimento elogio mural' },
    { title: 'Pessoas', url: 'r2_people_colaboradores_lista.html', cat: 'Pessoas', icon: '👥', kw: 'colaboradores lista equipe' },
    { title: 'Cadastrar pessoa', url: 'r2_people_colaborador.html', cat: 'Pessoas', icon: '👤', kw: 'novo colaborador admissao' },
    { title: 'Organograma', url: 'r2_people_estrutura.html', cat: 'Pessoas', icon: '🏛️', kw: 'estrutura departamentos cargos hierarquia' },
    { title: 'Avaliações', url: 'r2_people_avaliacao.html', cat: 'Desempenho', icon: '⭐', kw: 'avaliar performance' },
    { title: '9-Box · matriz de talentos', url: 'r2_people_9box.html', cat: 'Desempenho', icon: '🎯', kw: 'nine box potencial desempenho' },
    { title: 'PDI', url: 'r2_people_pdi.html', cat: 'Desempenho', icon: '📈', kw: 'plano desenvolvimento individual' },
    { title: 'OKRs', url: 'r2_people_okrs.html', cat: 'Desempenho', icon: '🚀', kw: 'objetivos key results checkins' },
    { title: '1:1s', url: 'r2_people_oneonones.html', cat: 'Desempenho', icon: '💬', kw: 'one on one conversa lider' },
    { title: 'Ciclos de avaliação', url: 'r2_people_ciclos.html', cat: 'Desempenho', icon: '🔄', kw: 'ciclo trimestre' },
    { title: 'Clima organizacional', url: 'r2_people_clima.html', cat: 'Pesquisas', icon: '🌡️', kw: 'pulso engajamento mood enps' },
    { title: 'Vagas internas', url: 'r2_people_vagas.html', cat: 'Carreira', icon: '💼', kw: 'jobs banco talentos indicacao' },
    { title: 'Treinamentos', url: 'r2_people_treinamentos.html', cat: 'Carreira', icon: '🎓', kw: 'cursos trilhas certificados aprendizado' },
    { title: 'Onboarding', url: 'r2_people_onboarding.html', cat: 'Carreira', icon: '🆕', kw: 'integracao novo' },
    { title: 'Atestados', url: 'r2_people_atestados.html', cat: 'Vida & Saúde', icon: '🩺', kw: 'medico medical doenca falta' },
    { title: 'Envio de atestado', url: 'r2_people_atestado_envio_lider.html', cat: 'Vida & Saúde', icon: '📄', kw: 'enviar atestado lider' },
    { title: 'Férias', url: 'r2_people_ferias.html', cat: 'Vida & Saúde', icon: '🏖️', kw: 'vacation planejamento' },
    { title: 'Programar férias', url: 'r2_people_ferias_programar.html', cat: 'Vida & Saúde', icon: '📅', kw: 'wizard ferias clt' },
    { title: 'Movimentações', url: 'r2_people_movimentacoes.html', cat: 'Vida & Saúde', icon: '↔️', kw: 'promocao transferencia aumento' },
    { title: 'Calculadora de custo', url: 'r2_people_calculadora_custo.html', cat: 'Folha & Custo', icon: '💰', kw: 'simulacao salario encargo' },
    { title: 'Folha por filial', url: 'r2_people_folha_por_filial.html', cat: 'Folha & Custo', icon: '🏪', kw: 'folha unidade' },
    { title: 'Regime tributário', url: 'r2_people_regime_tributario.html', cat: 'Folha & Custo', icon: '🧾', kw: 'simples lucro real tax cnpj' },
    { title: 'Comparar cenários', url: 'r2_people_comparar_cenarios.html', cat: 'Folha & Custo', icon: '⚖️', kw: 'a vs b dissidio' },
    { title: 'Relatórios', url: 'r2_people_relatorios.html', cat: 'Análise', icon: '📊', kw: 'report builder' },
    { title: 'Dashboard admin', url: 'r2_people_admin_dashboard.html', cat: 'Análise', icon: '📈', kw: 'kpi geral' },
    { title: 'Histórico de consulta', url: 'r2_people_historico_consulta.html', cat: 'Análise', icon: '🔍', kw: 'busca search' },
    { title: 'Auditoria · LGPD', url: 'r2_people_auditoria.html', cat: 'Admin', icon: '🔒', kw: 'log dpo audit lgpd dsar' },
    { title: 'Acessos e perfis', url: 'r2_people_acessos.html', cat: 'Admin', icon: '👮', kw: 'usuarios permissoes roles' },
    { title: 'Tenants · clientes', url: 'r2_people_tenants.html', cat: 'Admin', icon: '🏢', kw: 'super admin gpc filadelfia' },
    { title: 'Módulos do tenant', url: 'index.html', cat: 'Admin', icon: '🧩', kw: 'ativar desativar features' },
    { title: 'Configurações', url: 'r2_people_configuracoes.html', cat: 'Admin', icon: '⚙️', kw: 'settings tenant branding' },
    { title: 'Programa de indicação', url: 'r2_people_indicacoes.html', cat: 'Carreira', icon: '🤝', kw: 'indicar bonus referral R$ 1500' },
    { title: 'eNPS · Employee NPS', url: 'r2_people_enps.html', cat: 'Pesquisas', icon: '📊', kw: 'nps net promoter score recomenda' },
    { title: 'Cargos & Salários', url: 'r2_people_cargos_salarios.html', cat: 'Pessoas', icon: '💰', kw: 'matriz banda nivel cbo' },
    { title: 'Showcase · 57 telas', url: 'r2_people_showcase.html', cat: 'Home', icon: '🎨', kw: 'demo overview todas paginas visao geral' },
    { title: 'Importação', url: 'r2_people_importacao.html', cat: 'Admin', icon: '📥', kw: 'csv excel upload' },
    { title: 'Cockpit LGPD · DPO', url: 'r2_people_lgpd_cockpit.html', cat: 'Admin', icon: '🛡️', kw: 'dpo ropa dsar retencao consentimento sub operadores treinamento privacidade compliance' },
    { title: 'Notif. & Webhooks · Admin', url: 'r2_people_notificacoes_admin.html', cat: 'Admin', icon: '📡', kw: 'webhook dlq fila pgmq email runtime hmac retry catalogo eventos' },
    { title: 'Observability · SLOs & Incidentes', url: 'r2_people_observability_admin.html', cat: 'Admin', icon: '📈', kw: 'slo error budget incident postmortem alerta logs metrica grafana prometheus tempo cto' },
    { title: 'Security · DevSec Console', url: 'r2_people_security_admin.html', cat: 'Admin', icon: '🔒', kw: 'security devsec csp owasp vulnerability cve honeytoken secret rotacao pentest hardening' },
    { title: 'Hub Admin · operação consolidada', url: 'r2_people_admin_hub.html', cat: 'Admin', icon: '🎛️', kw: 'hub admin centro operacao consolidado cockpit landing entry point super admin' },
    { title: 'Tenant Setup · wizard de primeira execução', url: 'r2_people_tenant_setup.html', cat: 'Admin', icon: '🧙', kw: 'onboarding wizard tenant setup primeira execucao branding mfa configuracao inicial' },
    { title: 'Billing & Plano · tenant_admin', url: 'r2_people_billing.html', cat: 'Admin', icon: '💳', kw: 'billing plano fatura invoice assinatura subscription seat quota pagamento cartao pix upgrade' },
    { title: 'DR Console · Backups & Disaster Recovery', url: 'r2_people_dr_console.html', cat: 'Admin', icon: '🛟', kw: 'dr disaster recovery backup pitr restore drill smoke test rpo rto retention devops failover ransomware' },
    { title: 'Preços públicos · landing comercial', url: 'r2_people_pricing.html', cat: 'Home', icon: '💵', kw: 'preco pricing plano starter pro enterprise comercial landing publico marketing assinatura trial' }
  ];

  function openSearch() {
    var existing = document.querySelector('.r2-search-overlay');
    if (existing) { existing.remove(); return; }

    var overlay = document.createElement('div');
    overlay.className = 'r2-search-overlay';
    overlay.innerHTML =
      '<div class="r2-search-box" onclick="event.stopPropagation()">' +
        '<div class="r2-search-input-row">' +
          '<svg class="r2-search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>' +
          '<input class="r2-search-input" type="text" placeholder="Buscar páginas, pessoas, ações..." autofocus>' +
          '<kbd class="r2-search-kbd">esc</kbd>' +
        '</div>' +
        '<div class="r2-search-results" id="r2SearchResults"></div>' +
        '<div class="r2-search-footer">' +
          '<span><kbd>↑</kbd><kbd>↓</kbd> navegar</span>' +
          '<span><kbd>↵</kbd> abrir</span>' +
          '<span><kbd>esc</kbd> fechar</span>' +
          '<span style="margin-left:auto;">' + SEARCH_INDEX.length + ' páginas</span>' +
        '</div>' +
      '</div>';
    document.body.appendChild(overlay);

    var input = overlay.querySelector('.r2-search-input');
    var results = overlay.querySelector('#r2SearchResults');
    var current = 0;

    function render(query) {
      var q = (query || '').toLowerCase().trim();
      var matches = SEARCH_INDEX.filter(function(p){
        if (!q) return true;
        return p.title.toLowerCase().indexOf(q) > -1 ||
               p.cat.toLowerCase().indexOf(q) > -1 ||
               p.kw.indexOf(q) > -1;
      }).slice(0, 12);

      if (matches.length === 0) {
        results.innerHTML = '<div class="r2-search-empty">Nada encontrado para "<strong>' + escapeHtml(q) + '</strong>".</div>';
        return;
      }

      // Agrupar por categoria
      var byCat = {};
      matches.forEach(function(m){
        if (!byCat[m.cat]) byCat[m.cat] = [];
        byCat[m.cat].push(m);
      });

      var html = '';
      var idx = 0;
      Object.keys(byCat).forEach(function(cat){
        html += '<div class="r2-search-cat">' + cat + '</div>';
        byCat[cat].forEach(function(m){
          html += '<a class="r2-search-item' + (idx === current ? ' active' : '') + '" data-idx="' + idx + '" href="' + m.url + '">' +
            '<span class="r2-search-item-icon">' + m.icon + '</span>' +
            '<span class="r2-search-item-title">' + m.title + '</span>' +
            '<span class="r2-search-item-url">' + m.url + '</span>' +
          '</a>';
          idx++;
        });
      });
      results.innerHTML = html;
      window.__r2SearchItems = results.querySelectorAll('.r2-search-item');
    }

    function escapeHtml(s){ return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

    function close(){ overlay.remove(); }

    overlay.addEventListener('click', close);

    input.addEventListener('input', function(){
      current = 0;
      render(input.value);
    });

    input.addEventListener('keydown', function(e){
      var items = window.__r2SearchItems || [];
      if (e.key === 'Escape') { e.preventDefault(); close(); }
      else if (e.key === 'ArrowDown') {
        e.preventDefault();
        current = Math.min(current + 1, items.length - 1);
        items.forEach(function(it, i){ it.classList.toggle('active', i === current); });
        items[current] && items[current].scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        current = Math.max(current - 1, 0);
        items.forEach(function(it, i){ it.classList.toggle('active', i === current); });
        items[current] && items[current].scrollIntoView({ block: 'nearest' });
      } else if (e.key === 'Enter') {
        e.preventDefault();
        if (items[current]) window.location.href = items[current].href;
      }
    });

    render('');
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
      settings: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>',
      bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>',
      search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>'
    };
    return icons[name] || '';
  }

  // ============ Notifications dropdown ============
  var notifData = [
    { kind: 'pdi',    icon: '📈', title: 'PDI atualizado', desc: 'João Carvalho aprovou seu novo PDI Q2/2026',  time: 'há 12min', unread: true },
    { kind: 'okr',    icon: '🎯', title: 'Check-in vence sexta', desc: 'Você tem 3 KRs sem update há 7 dias',     time: 'há 2h',   unread: true },
    { kind: 'recog',  icon: '👏', title: 'Você foi reconhecida', desc: 'Patrícia Mello te reconheceu por entrega excepcional', time: 'há 5h', unread: true },
    { kind: 'oneonone', icon: '💬', title: '1:1 hoje 16h', desc: 'Sala com João Carvalho · auto-início em 3h', time: 'hoje', unread: false },
    { kind: 'climate', icon: '🌡️', title: 'Pulso semanal aberto', desc: 'Responda em 30s · fecha dom 24/mai', time: 'há 1d', unread: false }
  ];

  function toggleNotifications(anchor) {
    var existing = document.querySelector('.r2-notif-dropdown');
    if (existing) { existing.remove(); return; }

    var dd = document.createElement('div');
    dd.className = 'r2-notif-dropdown';
    dd.innerHTML =
      '<div class="r2-notif-header">' +
        '<strong>Notificações</strong>' +
        '<a href="r2_people_notificacoes.html">Ver todas</a>' +
      '</div>' +
      '<div class="r2-notif-list">' +
        notifData.map(function(n){
          return '<a class="r2-notif-item' + (n.unread ? ' unread' : '') + '" href="r2_people_notificacoes.html">' +
            '<span class="r2-notif-icon">' + n.icon + '</span>' +
            '<div class="r2-notif-body">' +
              '<div class="r2-notif-title">' + n.title + '</div>' +
              '<div class="r2-notif-desc">' + n.desc + '</div>' +
              '<div class="r2-notif-time">' + n.time + '</div>' +
            '</div>' +
          '</a>';
        }).join('') +
      '</div>' +
      '<div class="r2-notif-footer">' +
        '<button class="r2-notif-mark-all">Marcar todas como lidas</button>' +
      '</div>';
    document.body.appendChild(dd);

    // Posicionar logo abaixo do bell
    var r = anchor.getBoundingClientRect();
    dd.style.top = (r.bottom + 6) + 'px';
    dd.style.right = (window.innerWidth - r.right) + 'px';

    // Click fora fecha
    setTimeout(function(){
      document.addEventListener('click', function closeOnOutside(e){
        if (!dd.contains(e.target) && e.target !== anchor) {
          dd.remove();
          document.removeEventListener('click', closeOnOutside);
        }
      });
    }, 10);

    // Mark all as read
    dd.querySelector('.r2-notif-mark-all').addEventListener('click', function(){
      dd.querySelectorAll('.r2-notif-item.unread').forEach(function(it){ it.classList.remove('unread'); });
      var badge = document.querySelector('.r2-bell-badge');
      if (badge) badge.remove();
    });
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
