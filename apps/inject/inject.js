(function nexChamadosInject() {
  const MARK = 'data-nex-chamados';
  const BANNER_ID = 'nex-chamados-banner';
  const FRAME_ID = 'nex-chamados-frame';
  const DIALOG_ID = 'nex-chamados-dialog';
  const LOG = '[nex-chamados]';
  const ASSET_VERSION = '20260819d';
  const MOBILE_LAUNCHER_ID = 'nex-mobile-sidebar-launcher';
  const MOBILE_MQ = '(max-width: 767px)';
  const RESUMO_MAX = 255;
  const ASSUNTO_MAX = 2000;
  const SURFACE_FALLBACK = 'rgb(20, 21, 23)';
  const NAV_ROW = 'flex items-center gap-2 px-1.5 py-1 rounded-lg h-8 min-w-0';
  const NAV_ROW_COLLAPSED = 'flex items-center justify-center size-10 rounded-lg';
  const NAV_IDLE_CLASS = 'text-n-slate-11 hover:bg-n-alpha-2';
  const NAV_ACTIVE_CLASS = 'text-n-slate-12 bg-n-alpha-2 font-medium';
  const CLIPBOARD_ICON =
    '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="size-4" aria-hidden="true"><rect width="8" height="4" x="8" y="2" rx="1" ry="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M12 11h4"/><path d="M12 16h4"/><path d="M8 11h.01"/><path d="M8 16h.01"/></svg>';

  function accountIdFromLocation() {
    const parts = window.location.pathname.split('/');
    const index = parts.indexOf('accounts');
    if (index >= 0 && parts[index + 1]) {
      sessionStorage.setItem('nex_account_id', parts[index + 1]);
      return parts[index + 1];
    }
    return sessionStorage.getItem('nex_account_id') || '';
  }

  function conversationIdFromLocation() {
    const match = window.location.pathname.match(/\/conversations\/(\d+)/);
    return match ? match[1] : null;
  }

  function authHeaders() {
    const headers = { 'X-Account-Id': accountIdFromLocation(), Accept: 'application/json' };
    const raw = document.cookie.split('; ').find((item) => item.startsWith('cw_d_session_info='));
    if (!raw) return headers;
    try {
      const data = JSON.parse(decodeURIComponent(raw.split('=').slice(1).join('=')));
      if (data['access-token']) {
        headers['access-token'] = data['access-token'];
        headers['token-type'] = data['token-type'] || 'Bearer';
        headers.client = data.client;
        headers.expiry = data.expiry;
        headers.uid = data.uid;
      }
    } catch (error) {
      console.warn(LOG, 'cookie de sessão ilegível', error);
    }
    return headers;
  }

  async function apiGet(path) {
    const response = await fetch(`/chamados-api${path}`, {
      credentials: 'include',
      headers: authHeaders()
    });
    if (!response.ok) throw new Error(`API ${response.status}`);
    return response.json();
  }

  async function apiPost(path, body) {
    const response = await fetch(`/chamados-api${path}`, {
      method: 'POST',
      credentials: 'include',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error || `API ${response.status}`);
    return payload;
  }

  function navAside() {
    const item = document.querySelector(`aside [${MARK}="nav"]`);
    if (item) return item.closest('aside');
    return document.querySelector('aside');
  }

  function sidebarWidth() {
    const aside = navAside();
    return aside ? Math.round(aside.getBoundingClientRect().width) : 0;
  }

  function isMobileLayout() {
    return window.matchMedia(MOBILE_MQ).matches;
  }

  function visibleSidebarWidth() {
    const aside = navAside();
    if (!aside) return 0;
    const rect = aside.getBoundingClientRect();
    if (rect.right <= 0) return 0;
    return Math.round(rect.width);
  }

  let launcherHome = null;

  function nativeMobileLauncher() {
    return document.getElementById('mobile-sidebar-launcher');
  }

  function placeLauncher(node) {
    node.style.position = 'fixed';
    node.style.top = 'auto';
    node.style.right = 'auto';
    node.style.bottom = '16px';
    node.style.left = `${visibleSidebarWidth() + 16}px`;
    node.style.zIndex = '90';
    node.style.transform = 'none';
    node.style.visibility = 'visible';
    node.style.pointerEvents = 'auto';
  }

  function restoreNativeLauncher() {
    const native = nativeMobileLauncher();
    if (native && launcherHome && native.parentElement !== launcherHome) {
      launcherHome.appendChild(native);
    }
    if (native) {
      native.style.position = '';
      native.style.top = '';
      native.style.right = '';
      native.style.bottom = '';
      native.style.left = '';
      native.style.zIndex = '';
      native.style.transform = '';
      native.style.visibility = '';
      native.style.pointerEvents = '';
    }
    launcherHome = null;
  }

  function liftNativeLauncher() {
    const native = nativeMobileLauncher();
    if (!native) return false;
    if (native.parentElement !== document.body) {
      launcherHome = native.parentElement;
      document.body.appendChild(native);
    }
    placeLauncher(native);
    return true;
  }

  function setAsideOpen(open) {
    const aside = navAside();
    if (!aside) return;
    aside.style.transform = open ? 'translateX(0)' : 'translateX(-100%)';
  }

  function clearAsideOverride() {
    const aside = navAside();
    if (aside) aside.style.transform = '';
  }

  function removeMobileLauncher() {
    const node = document.getElementById(MOBILE_LAUNCHER_ID);
    if (node) node.remove();
    restoreNativeLauncher();
    clearAsideOverride();
  }

  function relayoutFrameSoon() {
    window.setTimeout(() => {
      const frame = frameElement();
      if (frame && frame.style.display !== 'none') applyFrameLayout(frame);
    }, 220);
  }

  function toggleFallbackSidebar(event) {
    event.preventDefault();
    event.stopPropagation();
    const aside = navAside();
    if (!aside) return;
    setAsideOpen(aside.getBoundingClientRect().right <= 0);
    relayoutFrameSoon();
  }

  function ensureMobileLauncher() {
    if (!isPanelOpen() || !isMobileLayout()) {
      removeMobileLauncher();
      return;
    }
    if (liftNativeLauncher()) {
      const extra = document.getElementById(MOBILE_LAUNCHER_ID);
      if (extra) extra.remove();
      return;
    }
    let node = document.getElementById(MOBILE_LAUNCHER_ID);
    if (!node) {
      node = document.createElement('div');
      node.id = MOBILE_LAUNCHER_ID;
      node.setAttribute(MARK, 'mobile-launcher');
      const button = document.createElement('button');
      button.type = 'button';
      button.setAttribute('aria-label', 'Abrir ou fechar o menu');
      button.style.cssText =
        'display:flex;align-items:center;justify-content:center;width:48px;height:48px;padding:0;border:0;border-radius:999px;background:rgba(32,34,40,0.92);color:#edeef0;box-shadow:0 8px 24px rgba(0,0,0,0.35);cursor:pointer;';
      button.innerHTML =
        '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"/></svg>';
      button.addEventListener('pointerdown', toggleFallbackSidebar, true);
      button.addEventListener('click', toggleFallbackSidebar, true);
      node.appendChild(button);
      document.body.appendChild(node);
    }
    placeLauncher(node);
  }

  function isSidebarCollapsed() {
    return sidebarWidth() < 80;
  }

  function frameElement() {
    return document.getElementById(FRAME_ID);
  }

  function isPanelOpen() {
    const frame = frameElement();
    return Boolean(frame && frame.style.display !== 'none');
  }

  function rgbLuminance(color) {
    const match = String(color).match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    if (!match) return 1;
    return (0.2126 * Number(match[1]) + 0.7152 * Number(match[2]) + 0.0722 * Number(match[3])) / 255;
  }

  function isDarkSurface(color) {
    return Boolean(color) && color !== 'transparent' && !color.includes('0, 0, 0, 0') && rgbLuminance(color) < 0.45;
  }

  function chatwootSurfaceColor() {
    const sample =
      document.querySelector('.conversations-list-wrap') ||
      document.querySelector('.conversation-details-wrap');
    if (sample && sample.getBoundingClientRect().height > 0) {
      const painted = getComputedStyle(sample).backgroundColor;
      if (isDarkSurface(painted)) return painted;
    }
    return SURFACE_FALLBACK;
  }

  function paintProtocolosDocument(doc, color) {
    if (!doc) return;
    doc.documentElement.style.setProperty('--bg', color);
    doc.documentElement.style.setProperty('--card', color);
    doc.documentElement.style.setProperty('--surface', color);
    doc.documentElement.style.background = color;
    if (doc.body) doc.body.style.background = color;
    const app = doc.getElementById('app');
    if (app) app.style.background = color;
  }

  function paintProtocolosFrame(frame) {
    const color = chatwootSurfaceColor();
    frame.style.background = color;
    paintProtocolosDocument(frame.contentDocument, color);
  }

  function watchFramePaint(frame) {
    if (frame.getAttribute(`${MARK}-paint`) === '1') return;
    frame.setAttribute(`${MARK}-paint`, '1');
    frame.addEventListener('load', () => paintProtocolosFrame(frame));
  }

  function applyFrameLayout(frame) {
    const left = visibleSidebarWidth();
    // iframe ignora left+right com width:auto — precisa de largura explícita
    frame.style.position = 'fixed';
    frame.style.top = '0';
    frame.style.left = `${left}px`;
    frame.style.right = 'auto';
    frame.style.bottom = 'auto';
    frame.style.width = `calc(100vw - ${left}px)`;
    frame.style.height = '100vh';
    frame.style.border = '0';
    frame.style.zIndex = '80';
    frame.style.colorScheme = 'dark';
    paintProtocolosFrame(frame);
    ensureMobileLauncher();
  }

  function navRow(item) {
    return item.querySelector(`[${MARK}="nav-row"]`);
  }

  function applyNavAppearance(item, active) {
    const row = navRow(item);
    if (!row) return;
    const collapsed = isSidebarCollapsed();
    row.className = `${collapsed ? NAV_ROW_COLLAPSED : NAV_ROW} ${active ? NAV_ACTIVE_CLASS : NAV_IDLE_CLASS}`;
    const label = row.querySelector(`[${MARK}="nav-label"]`);
    if (label) label.hidden = collapsed;
  }

  function setNavActive(active) {
    const item = document.querySelector(`[${MARK}="nav"]`);
    if (item) applyNavAppearance(item, active);
  }

  function closePanel() {
    const frame = frameElement();
    if (frame) frame.style.display = 'none';
    setNavActive(false);
    removeMobileLauncher();
  }

  function chamadosPath(path) {
    const url = new URL(path, window.location.origin);
    const accountId = accountIdFromLocation();
    if (accountId) url.searchParams.set('account_id', accountId);
    url.searchParams.set('v', ASSET_VERSION);
    return `${url.pathname}${url.search}`;
  }

  function hideContactSidebar() {
    const list = document.querySelector('.list-group');
    if (!list) return;
    const root = list.closest('.h-full');
    const header = root?.querySelector('.h-12');
    const closeBtn = header?.querySelector('button:last-of-type');
    if (closeBtn) closeBtn.click();
  }

  function openPanel(path) {
    let frame = frameElement();
    if (!frame) {
      frame = document.createElement('iframe');
      frame.id = FRAME_ID;
      frame.title = 'Chamados';
      frame.setAttribute('allow', 'microphone');
      frame.setAttribute(MARK, 'frame');
      document.body.appendChild(frame);
      watchFramePaint(frame);
    }
    const next = chamadosPath(path);
    watchFramePaint(frame);
    applyFrameLayout(frame);
    frame.style.display = 'block';
    setNavActive(true);
    hideContactSidebar();
    frame.src = next;
    frame.setAttribute('data-src', next);
  }

  function goToList() {
    openPanel('/chamados/');
  }

  function fieldBlock(label, control) {
    const wrap = document.createElement('label');
    wrap.style.cssText = 'display:flex;flex-direction:column;gap:4px;min-width:0';
    const caption = document.createElement('span');
    caption.textContent = label;
    caption.style.cssText = 'color:#b0b4ba;font-size:12px;font-weight:500';
    wrap.appendChild(caption);
    wrap.appendChild(control);
    return wrap;
  }

  function styledControl(tag, attrs) {
    const node = document.createElement(tag);
    Object.entries(attrs).forEach(([key, value]) => {
      if (key === 'options') return;
      node[key] = value;
    });
    node.style.cssText =
      'width:100%;box-sizing:border-box;height:32px;background:rgba(255,255,255,0.02);border:0;outline:1px solid #2e2d32;color:#edeef0;border-radius:8px;padding:0 10px;font:13px Inter,system-ui,sans-serif';
    (attrs.options || []).forEach((option) => {
      const item = document.createElement('option');
      item.value = option.value;
      item.textContent = option.label;
      node.appendChild(item);
    });
    return node;
  }

  function styledTextarea(attrs) {
    const node = document.createElement('textarea');
    Object.entries(attrs).forEach(([key, value]) => {
      node[key] = value;
    });
    node.style.cssText =
      'width:100%;box-sizing:border-box;min-height:80px;resize:vertical;background:rgba(255,255,255,0.02);border:0;outline:1px solid #2e2d32;color:#edeef0;border-radius:8px;padding:8px 10px;font:13px Inter,system-ui,sans-serif';
    return node;
  }

  function attachCharCounter(field, control, max) {
    const counter = document.createElement('span');
    counter.style.cssText = 'align-self:flex-end;color:#b0b4ba;font-size:12px';
    const update = () => {
      counter.textContent = `${control.value.length}/${max}`;
    };
    control.addEventListener('input', update);
    update();
    field.appendChild(counter);
    return field;
  }

  function closeCreateDialog() {
    const dialog = document.getElementById(DIALOG_ID);
    if (dialog) dialog.remove();
  }

  function attributeControl(attr) {
    if (attr.type === 'list') {
      const options = [{ value: '', label: '—' }].concat(
        (attr.options || []).map((value) => ({ value, label: value }))
      );
      const select = styledControl('select', { options });
      select.value = attr.value == null ? '' : String(attr.value);
      return select;
    }
    if (attr.type === 'checkbox') {
      const input = styledControl('input', { type: 'checkbox' });
      input.style.width = 'auto';
      input.checked = attr.value === true || attr.value === 'true';
      return input;
    }
    const input = styledControl('input', {
      type: attr.type === 'date' ? 'date' : 'text',
      placeholder: attr.description || ''
    });
    input.value = attr.value == null ? '' : String(attr.value);
    return input;
  }

  function readAttributeValue(attr, control) {
    if (attr.type === 'checkbox') return control.checked;
    return control.value;
  }

  function openCreateDialog(conversationId) {
    closeCreateDialog();
    const overlay = document.createElement('div');
    overlay.id = DIALOG_ID;
    overlay.style.cssText =
      'position:fixed;inset:0;z-index:200;background:rgba(0,0,0,0.55);display:flex;align-items:center;justify-content:center;padding:24px';
    overlay.addEventListener('click', (event) => {
      if (event.target === overlay) closeCreateDialog();
    });
    const onEscape = (event) => {
      if (event.key !== 'Escape') return;
      closeCreateDialog();
      document.removeEventListener('keydown', onEscape);
    };
    document.addEventListener('keydown', onEscape);

    const card = document.createElement('div');
    card.setAttribute('role', 'dialog');
    card.setAttribute('aria-labelledby', 'nex-chamados-dialog-title');
    card.style.cssText =
      'width:min(720px,100%);max-height:90vh;display:flex;flex-direction:column;overflow:hidden;background:#1c1e22;border:1px solid #1f1f25;border-radius:12px;padding:24px;color:#edeef0;font:14px Inter,system-ui,sans-serif;box-shadow:0 16px 40px rgba(0,0,0,0.4)';

    const title = document.createElement('h2');
    title.id = 'nex-chamados-dialog-title';
    title.textContent = 'Criar chamado';
    title.style.cssText = 'margin:0;flex-shrink:0;font-size:18px;font-weight:500';

    const subtitle = document.createElement('p');
    subtitle.textContent = `Abre um chamado na conversa #${conversationId}`;
    subtitle.style.cssText = 'margin:6px 0 20px;flex-shrink:0;color:#b0b4ba;font-size:13px';

    const summary = styledControl('input', { placeholder: 'Resumo do caso', maxLength: RESUMO_MAX });
    const summaryField = attachCharCounter(fieldBlock('Resumo (opcional)', summary), summary, RESUMO_MAX);
    const assunto = styledTextarea({ placeholder: 'Motivo da abertura do chamado', maxLength: ASSUNTO_MAX });
    const assuntoField = attachCharCounter(fieldBlock('Assunto', assunto), assunto, ASSUNTO_MAX);
    const priority = styledControl('select', {
      options: [
        { value: '', label: 'Nenhuma' },
        { value: 'baixa', label: 'Baixa' },
        { value: 'media', label: 'Média' },
        { value: 'alta', label: 'Alta' }
      ]
    });
    const dueOn = styledControl('input', { type: 'date' });
    const notify = styledControl('select', {
      options: [
        { value: 'none', label: 'Não enviar' },
        { value: 'chat', label: 'Mensagem no chat' },
        { value: 'note', label: 'Nota privada' }
      ]
    });

    const attributeFields = [];
    const attributesBox = document.createElement('div');
    attributesBox.style.cssText =
      'display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px 16px';

    const error = document.createElement('p');
    error.style.cssText = 'display:none;margin:0;color:#ff949d;font-size:13px';

    const actions = document.createElement('div');
    actions.style.cssText = 'display:flex;justify-content:flex-end;gap:8px;margin-top:16px;flex-shrink:0';

    const cancel = document.createElement('button');
    cancel.type = 'button';
    cancel.textContent = 'Cancelar';
    cancel.style.cssText =
      'height:32px;padding:0 12px;border:0;border-radius:8px;background:transparent;color:#edeef0;outline:1px solid #2e2d32;cursor:pointer;font:500 13px Inter,system-ui,sans-serif';
    cancel.addEventListener('click', closeCreateDialog);

    const submit = document.createElement('button');
    submit.type = 'button';
    submit.textContent = 'Criar e abrir chamado';
    submit.style.cssText =
      'height:32px;padding:0 12px;border:0;border-radius:8px;background:#2781f6;color:#fff;cursor:pointer;font:500 13px Inter,system-ui,sans-serif';
    submit.addEventListener('click', async () => {
      error.style.display = 'none';
      if (!assunto.value.trim()) {
        error.textContent = 'Assunto obrigatório';
        error.style.display = 'block';
        return;
      }
      submit.disabled = true;
      try {
        const contactAttributes = {};
        attributeFields.forEach(({ attr, control }) => {
          contactAttributes[attr.key] = readAttributeValue(attr, control);
        });
        const created = await apiPost('/chamados', {
          conversation_id: conversationId,
          subject: summary.value,
          assunto: assunto.value,
          priority: priority.value,
          due_on: dueOn.value,
          notify: notify.value,
          contact_attributes: contactAttributes
        });
        closeCreateDialog();
        goToDossier(created.number);
        syncConversation();
      } catch (err) {
        error.textContent = err.message;
        error.style.display = 'block';
        submit.disabled = false;
      }
    });

    actions.appendChild(cancel);
    actions.appendChild(submit);

    const metaRow = document.createElement('div');
    metaRow.style.cssText =
      'display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px 16px';
    metaRow.appendChild(fieldBlock('Prioridade', priority));
    metaRow.appendChild(fieldBlock('Prazo', dueOn));
    metaRow.appendChild(fieldBlock('Avisar', notify));

    const form = document.createElement('div');
    form.style.cssText =
      'display:flex;flex-direction:column;gap:16px;overflow:auto;flex:1;min-height:0;padding-right:4px';
    form.appendChild(summaryField);
    form.appendChild(assuntoField);
    form.appendChild(metaRow);
    form.appendChild(attributesBox);
    form.appendChild(error);

    card.appendChild(title);
    card.appendChild(subtitle);
    card.appendChild(form);
    card.appendChild(actions);
    overlay.appendChild(card);
    document.body.appendChild(overlay);
    summary.focus();

    apiGet(`/conversations/${conversationId}/contact-attributes`)
      .then((payload) => {
        const items = payload.attributes || [];
        if (!items.length) return;
        const heading = document.createElement('p');
        heading.textContent = 'Atributos do contato';
        heading.style.cssText =
          'margin:4px 0 0;padding-top:12px;border-top:1px solid #1f1f25;color:#b0b4ba;font-size:12px;font-weight:500;grid-column:1 / -1';
        attributesBox.appendChild(heading);
        items.forEach((attr) => {
          const control = attributeControl(attr);
          attributeFields.push({ attr, control });
          attributesBox.appendChild(fieldBlock(attr.label, control));
        });
      })
      .catch((err) => {
        console.warn(LOG, 'atributos do contato', err);
      });
  }

  function goToNew(conversationId) {
    openCreateDialog(conversationId);
  }

  function goToDossier(number) {
    openPanel(`/chamados/${encodeURIComponent(number)}`);
  }

  function findConversasGroup(aside) {
    const candidates = aside.querySelectorAll('li, div, a, button, span');
    for (const node of candidates) {
      const text = (node.textContent || '').trim();
      if (text === 'Conversas' || text === 'Conversations') {
        return node.closest('li') || node.parentElement;
      }
    }
    return null;
  }

  function buildNavItem() {
    const item = document.createElement('li');
    item.setAttribute(MARK, 'nav');
    item.className = 'grid gap-1 text-sm cursor-pointer select-none min-w-0';
    item.innerHTML = `<div ${MARK}="nav-row" role="button" title="Chamados">${CLIPBOARD_ICON}<span ${MARK}="nav-label" class="truncate">Chamados</span></div>`;
    applyNavAppearance(item, isPanelOpen());
    item.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      goToList();
    });
    return item;
  }

  function insertNav(aside) {
    const existing = aside.querySelector(`[${MARK}="nav"]`);
    if (existing) {
      applyNavAppearance(existing, isPanelOpen());
      return true;
    }
    const conversas = findConversasGroup(aside);
    if (!conversas) return false;
    const parent = conversas.parentElement;
    if (!parent) return false;
    const item = buildNavItem();
    if (conversas.nextSibling) parent.insertBefore(item, conversas.nextSibling);
    else parent.appendChild(item);
    hideBanner();
    return true;
  }

  function showBanner() {
    if (document.getElementById(BANNER_ID)) return;
    const banner = document.createElement('div');
    banner.id = BANNER_ID;
    banner.style.cssText =
      'position:fixed;top:0;left:0;right:0;z-index:9999;background:#2781f6;color:#fff;padding:8px 16px;font:14px Inter,system-ui,sans-serif';
    banner.innerHTML =
      'Chamados: o menu não foi encontrado. <a href="#" style="color:#fff;text-decoration:underline">Abrir chamados</a>';
    banner.querySelector('a').addEventListener('click', (event) => {
      event.preventDefault();
      goToList();
    });
    document.body.prepend(banner);
    console.warn(LOG, 'sidebar sem âncora Conversas; banner ativo');
  }

  function hideBanner() {
    const banner = document.getElementById(BANNER_ID);
    if (banner) banner.remove();
  }

  function ensureNav() {
    const aside = document.querySelector('aside');
    if (!aside) {
      showBanner();
      return;
    }
    if (!insertNav(aside)) showBanner();
    if (aside.getAttribute(`${MARK}-layout`) !== '1') {
      aside.setAttribute(`${MARK}-layout`, '1');
      aside.addEventListener('transitionend', () => {
        const frame = frameElement();
        if (frame && frame.style.display !== 'none') applyFrameLayout(frame);
      });
    }
    const frame = frameElement();
    if (frame && frame.style.display !== 'none') applyFrameLayout(frame);
  }

  function blockDeleteIfLinked(protocols) {
    const hasActiveLink = protocols.some((item) => item.conversations?.some((conv) => !conv.removed));
    if (!hasActiveLink) return;
    document.querySelectorAll('button, a, [role="menuitem"]').forEach((node) => {
      const text = (node.textContent || '').toLowerCase();
      if (!text.includes('excluir') && !text.includes('delete') && !text.includes('apagar')) return;
      if (node.getAttribute(MARK) === 'delete-blocked') return;
      node.setAttribute(MARK, 'delete-blocked');
      node.addEventListener(
        'click',
        (event) => {
          event.preventDefault();
          event.stopPropagation();
          window.alert('Esta conversa está vinculada a um chamado. Feche a conversa; não apague.');
        },
        true
      );
    });
  }

  const STATUS_LABELS = {
    pendente: 'Pendente',
    em_atendimento: 'Em atendimento',
    resolvido: 'Resolvido',
    cancelado: 'Cancelado'
  };

  let lastProtocols = [];
  let sidebarOpen = false;

  function removeConversationUi() {
    document.querySelectorAll(`[${MARK}="header"], [${MARK}="sidebar"]`).forEach((node) => node.remove());
  }

  function removeConversationBars() {
    removeConversationUi();
  }

  function findBarHost() {
    const actions =
      document.querySelector('.header-actions-wrap .actions--container') ||
      document.querySelector('.actions--container') ||
      document.querySelector('.header-actions-wrap');
    return actions ? { host: actions } : null;
  }

  function headerButton(label, variant) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = label;
    button.style.cssText =
      variant === 'primary'
        ? 'height:32px;padding:0 12px;border:0;border-radius:8px;font:500 13px/1 Inter,system-ui,sans-serif;cursor:pointer;flex-shrink:0;white-space:nowrap;background:#2781f6;color:#fff'
        : 'height:32px;padding:0 12px;border:0;border-radius:8px;font:500 13px/1 Inter,system-ui,sans-serif;cursor:pointer;flex-shrink:0;white-space:nowrap;background:transparent;color:#edeef0;outline:1px solid #2e2d32';
    return button;
  }

  function renderConversationBar(protocols) {
    removeConversationBars();
    const target = findBarHost();
    if (!target) return;

    const bar = document.createElement('div');
    bar.setAttribute(MARK, 'header');
    bar.style.cssText = 'display:flex;align-items:center;gap:8px;flex-shrink:0';

    const createBtn = headerButton('Criar chamado', 'primary');
    createBtn.addEventListener('click', () => goToNew(conversationIdFromLocation()));
    bar.appendChild(createBtn);

    if (!protocols.length) {
      const linkBtn = headerButton('Vincular a existente', 'slate');
      linkBtn.addEventListener('click', () => goToList());
      bar.appendChild(linkBtn);
    }

    target.host.prepend(bar);
    blockDeleteIfLinked(protocols);
  }

  function findContactAccordionHost() {
    return document.querySelector('.list-group .flex.flex-col') || document.querySelector('.list-group');
  }

  function statusText(status) {
    return STATUS_LABELS[status] || status;
  }

  function renderContactAccordion(protocols) {
    const existing = document.querySelector(`[${MARK}="sidebar"]`);
    if (existing) existing.remove();
    const host = findContactAccordionHost();
    if (!host) return;

    const wrap = document.createElement('div');
    wrap.setAttribute(MARK, 'sidebar');
    wrap.className = 'text-sm';

    const toggle = document.createElement('button');
    toggle.type = 'button';
    toggle.className =
      'flex items-center select-none w-full rounded-lg bg-n-slate-2 outline outline-1 outline-n-weak m-0 justify-between py-2 px-4';
    if (sidebarOpen) toggle.classList.add('rounded-bl-none', 'rounded-br-none');

    const title = document.createElement('h5');
    title.className = 'text-n-slate-12 text-sm mb-0 py-0';
    title.textContent = 'Chamados vinculados';

    const icon = document.createElement('span');
    icon.className = 'text-n-blue-11 text-lg leading-none';
    icon.textContent = sidebarOpen ? '−' : '+';

    toggle.appendChild(title);
    toggle.appendChild(icon);

    const body = document.createElement('div');
    body.className = 'outline outline-1 outline-n-weak px-2 py-3 rounded-br-lg rounded-bl-lg';
    body.hidden = !sidebarOpen;

    if (!protocols.length) {
      const empty = document.createElement('p');
      empty.className = 'text-n-slate-11 text-sm m-0 px-2';
      empty.textContent = 'Nenhum chamado vinculado';
      body.appendChild(empty);
    } else {
      protocols.forEach((item) => {
        const row = document.createElement('button');
        row.type = 'button';
        row.className =
          'flex w-full items-center justify-between gap-2 rounded-lg px-2 py-2 text-left text-n-slate-12 hover:bg-n-alpha-2';
        row.innerHTML = `<span class="truncate">${item.number}</span><span class="shrink-0 whitespace-nowrap text-n-slate-11 text-xs">${statusText(item.status)}</span>`;
        row.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          goToDossier(item.number);
        });
        body.appendChild(row);
      });
    }

    toggle.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      sidebarOpen = !sidebarOpen;
      body.hidden = !sidebarOpen;
      icon.textContent = sidebarOpen ? '−' : '+';
      toggle.classList.toggle('rounded-bl-none', sidebarOpen);
      toggle.classList.toggle('rounded-br-none', sidebarOpen);
    });

    wrap.appendChild(toggle);
    wrap.appendChild(body);
    host.prepend(wrap);
  }

  function renderConversationUi(protocols) {
    lastProtocols = protocols;
    renderConversationBar(protocols);
    renderContactAccordion(protocols);
  }

  async function syncConversation() {
    const conversationId = conversationIdFromLocation();
    if (!conversationId || !accountIdFromLocation()) {
      lastProtocols = [];
      removeConversationUi();
      return;
    }
    try {
      const payload = await apiGet(`/chamados/by-conversation/${conversationId}`);
      renderConversationUi(payload.items || []);
    } catch (error) {
      console.warn(LOG, 'falha ao carregar chamados da conversa', error);
    }
  }

  function watchChatwootNavigation() {
    document.addEventListener(
      'click',
      (event) => {
        const aside = document.querySelector('aside');
        if (!aside || !aside.contains(event.target)) return;
        if (event.target.closest(`[${MARK}="nav"]`)) return;
        closePanel();
      },
      true
    );
  }

  function watchParentMessages() {
    window.addEventListener('message', (event) => {
      if (event.origin !== window.location.origin) return;
      if (event.data?.source !== 'nex-chamados') return;
      if (event.data.action !== 'open-conversation' || !event.data.url) return;
      const next = new URL(event.data.url, window.location.origin);
      closePanel();
      if (window.location.pathname === next.pathname) return;
      window.location.assign(next.pathname + next.search);
    });
  }

  function watchLocation() {
    let lastPath = window.location.pathname;
    const onChange = () => {
      if (window.location.pathname === lastPath) return;
      lastPath = window.location.pathname;
      if (!conversationIdFromLocation()) removeConversationBars();
      else syncConversation();
    };
    ['pushState', 'replaceState'].forEach((method) => {
      const original = history[method];
      history[method] = function patchedHistory() {
        const result = original.apply(this, arguments);
        onChange();
        return result;
      };
    });
    window.addEventListener('popstate', onChange);
  }

  function start() {
    accountIdFromLocation();
    ensureNav();
    syncConversation();
    watchChatwootNavigation();
    watchParentMessages();
    watchLocation();
    window.addEventListener('resize', () => {
      const frame = frameElement();
      if (frame && frame.style.display !== 'none') applyFrameLayout(frame);
      setNavActive(isPanelOpen());
    });
    let syncTimer = null;
    const observer = new MutationObserver(() => {
      ensureNav();
      if (!conversationIdFromLocation()) {
        removeConversationUi();
        return;
      }
      const needHeader = !document.querySelector(`[${MARK}="header"]`) && findBarHost();
      const needSidebar = !document.querySelector(`[${MARK}="sidebar"]`) && findContactAccordionHost();
      if (!needHeader && !needSidebar) return;
      if (needSidebar && !needHeader) {
        renderContactAccordion(lastProtocols);
        return;
      }
      if (syncTimer) return;
      syncTimer = setTimeout(() => {
        syncTimer = null;
        syncConversation();
      }, 150);
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start);
  } else {
    start();
  }
})();
