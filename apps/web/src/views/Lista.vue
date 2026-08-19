<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import ConfirmDialog from '../components/ConfirmDialog.vue';
import ContextMenu from '../components/ContextMenu.vue';
import FilterPopover from '../components/FilterPopover.vue';
import NamesOverflow from '../components/NamesOverflow.vue';
import ReasonDialog from '../components/ReasonDialog.vue';
import SelectDropdown from '../components/SelectDropdown.vue';
import { api } from '../api.js';
import { openAgeForItem } from '../openAge.js';
import { PRIORITY_LABELS, priorityLabel } from '../priority.js';
import { statusLabel } from '../status.js';

const PAGE_SIZES = [10, 25, 50, 100];
const SEARCH_DEBOUNCE_MS = 300;
const OPEN_AGE_TICK_MS = 30_000;

const router = useRouter();
const error = ref('');
const users = ref([]);
const currentUserId = ref(null);
const session = ref(null);
const now = ref(Date.now());
const data = ref({ items: [], total: 0, page: 1, per_page: 10 });
const contextMenu = ref({ open: false, x: 0, y: 0, item: null });
const pendingLeave = ref(null);
const pendingDelete = ref(null);
const filters = reactive({
  user_id: '',
  q: '',
  status: [],
  priority: [],
  sort: 'updated',
  page: 1,
  per_page: 10,
  trashed: false
});
const ALL_USERS = 'todos';
const isAllUsers = computed(() => filters.user_id === ALL_USERS);
const isAdmin = computed(() => {
  const account = session.value?.accounts?.find((acc) => String(acc.id) === String(api.accountId()));
  return account?.role === 'administrator';
});
const emptyMessage = computed(() => {
  if (filters.trashed) return 'Nenhum chamado na lixeira.';
  if (isAllUsers.value) return 'Nenhum chamado na conta.';
  if (String(filters.user_id) === String(currentUserId.value)) return 'Você não tem chamados.';
  return 'Este usuário não tem chamados.';
});
const userOptions = computed(() => [
  { value: ALL_USERS, label: 'Todos' },
  ...users.value.map((user) => ({ value: user.id, label: user.name }))
]);
const sortOptions = [
  { value: 'updated', label: 'Atualização' },
  { value: 'number', label: 'Número' },
  { value: 'status', label: 'Status' }
];
const pageSizeOptions = PAGE_SIZES.map((size) => ({ value: size, label: String(size) }));
const hasExtraFilters = computed(
  () =>
    filters.status.length > 0 ||
    filters.priority.length > 0 ||
    filters.sort !== 'updated' ||
    filters.trashed
);

const totalPages = computed(() => Math.max(1, Math.ceil((data.value.total || 0) / (data.value.per_page || 1))));
const rangeStart = computed(() => (data.value.total === 0 ? 0 : (data.value.page - 1) * data.value.per_page + 1));
const rangeEnd = computed(() => Math.min(data.value.page * data.value.per_page, data.value.total));
const pageItems = computed(() => visiblePageItems(data.value.page, totalPages.value));

function visiblePageItems(current, pageCount) {
  if (pageCount <= 1) return pageCount === 1 ? [1] : [];
  if (pageCount <= 7) return Array.from({ length: pageCount }, (_, index) => index + 1);

  let start = Math.max(2, current - 1);
  let end = Math.min(pageCount - 1, current + 1);
  if (current <= 3) {
    start = 2;
    end = 3;
  }
  if (current >= pageCount - 2) {
    start = pageCount - 2;
    end = pageCount - 1;
  }

  const items = [1];
  if (start > 2) items.push('…');
  for (let page = start; page <= end; page += 1) items.push(page);
  if (end < pageCount - 1) items.push('…');
  items.push(pageCount);
  return items;
}

function goToPage(page) {
  if (page < 1 || page > totalPages.value || page === filters.page) return;
  filters.page = page;
  load();
}

function changePageSize() {
  filters.page = 1;
  load();
}
const statusOptions = [
  { value: 'pendente', label: 'Pendente' },
  { value: 'em_atendimento', label: 'Em atendimento' },
  { value: 'resolvido', label: 'Resolvido' },
  { value: 'cancelado', label: 'Cancelado' }
];
const priorityOptions = Object.entries(PRIORITY_LABELS).map(([value, label]) => ({ value, label }));

async function load() {
  error.value = '';
  try {
    const query = {
      user_id: filters.user_id,
      q: filters.q,
      status: filters.status.join(','),
      priority: filters.priority.join(','),
      sort: filters.sort,
      page: filters.page,
      per_page: filters.per_page
    };
    if (filters.trashed) query.trashed = '1';
    data.value = await api.list(query);
  } catch (err) {
    error.value = err.message;
  }
}

function sortUsers(items, loggedUserId) {
  return items.slice().sort((left, right) => {
    if (left.id === loggedUserId) return -1;
    if (right.id === loggedUserId) return 1;
    return String(left.name).localeCompare(String(right.name), 'pt-BR');
  });
}

async function loadUsers(currentUser) {
  try {
    const payload = await api.users();
    const items = Array.isArray(payload.items) ? payload.items.slice() : [];
    if (!items.some((user) => user.id === currentUser.id)) {
      items.unshift({ id: currentUser.id, name: currentUser.name, email: currentUser.email });
    }
    return sortUsers(items, currentUser.id);
  } catch (err) {
    console.warn('Não foi possível listar usuários da conta', err);
    return [{ id: currentUser.id, name: currentUser.name, email: currentUser.email }];
  }
}

async function bootstrap() {
  try {
    session.value = await api.session();
    currentUserId.value = session.value.user.id;
    filters.user_id = session.value.user.id;
    users.value = await loadUsers(session.value.user);
  } catch (err) {
    error.value = err.message;
    return;
  }
  await load();
}

function changeUser() {
  filters.page = 1;
  load();
}

function changeTrash() {
  filters.page = 1;
  load();
}

let searchTimer = null;
let ageTimer = null;

function searchNow() {
  if (searchTimer) {
    window.clearTimeout(searchTimer);
    searchTimer = null;
  }
  filters.page = 1;
  load();
}

watch(
  () => filters.q,
  () => {
    if (searchTimer) window.clearTimeout(searchTimer);
    searchTimer = window.setTimeout(searchNow, SEARCH_DEBOUNCE_MS);
  }
);

function formatDueOn(value) {
  if (!value) return '—';
  const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) return `${match[3]}/${match[2]}/${match[1]}`;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleDateString('pt-BR');
}

function participanteNames(item) {
  return (item.participantes || [])
    .map((member) => {
      if (member && typeof member === 'object') return member.name || (member.id ? `#${member.id}` : '');
      const user = users.value.find((entry) => String(entry.id) === String(member));
      return user?.name || (member ? `#${member}` : '');
    })
    .filter(Boolean);
}

function creatorName(item) {
  if (item.opened_by?.name) return item.opened_by.name;
  const userId = item.opened_by?.id ?? item.opened_by_user_id;
  if (!userId) return '—';
  const user = users.value.find((entry) => String(entry.id) === String(userId));
  return user?.name || `#${userId}`;
}

function openAgeLabel(item) {
  return openAgeForItem(item, now.value);
}

function changeStatus() {
  filters.page = 1;
  load();
}

function memberIncludes(members, userId) {
  return (members || []).some((member) => String(member.id ?? member) === String(userId));
}

function buildMenuItems(item) {
  if (!item) return [];
  if (item.deleted_at) {
    return isAdmin.value ? [{ id: 'restore', label: 'Restaurar', icon: 'restore' }] : [];
  }
  const items = [];
  if (!memberIncludes(item.participantes, currentUserId.value)) {
    items.push({ id: 'assume', label: 'Assumir', icon: 'assume' });
  }
  if (memberIncludes(item.watchers, currentUserId.value)) {
    items.push({ id: 'unwatch', label: 'Parar de observar', icon: 'unwatch' });
  } else {
    items.push({ id: 'watch', label: 'Observar', icon: 'watch' });
  }
  if (memberIncludes(item.participantes, currentUserId.value)) {
    items.push({ id: 'leave', label: 'Abandonar', icon: 'leave', danger: true });
  }
  if (isAdmin.value) {
    items.push({ divider: true });
    items.push({ id: 'delete', label: 'Apagar', icon: 'delete', danger: true });
  }
  return items;
}

const menuItems = computed(() => buildMenuItems(contextMenu.value.item));

function closeContextMenu() {
  contextMenu.value = { open: false, x: 0, y: 0, item: null };
}

function openContextMenu(event, item) {
  event.preventDefault();
  if (!buildMenuItems(item).length) return;
  contextMenu.value = { open: true, x: event.clientX, y: event.clientY, item };
}

async function runAction(action) {
  error.value = '';
  try {
    await action();
    await load();
  } catch (err) {
    error.value = err.message;
  }
}

const immediateActions = {
  assume: (item) => api.assume(item.number),
  watch: (item) => api.watch(item.number),
  unwatch: (item) => api.unwatch(item.number),
  restore: (item) => api.restore(item.number)
};

async function onMenuSelect(option) {
  const item = contextMenu.value.item;
  closeContextMenu();
  if (!item) return;
  if (option.id === 'leave') {
    pendingLeave.value = item;
    return;
  }
  if (option.id === 'delete') {
    pendingDelete.value = item;
    return;
  }
  const action = immediateActions[option.id];
  if (action) await runAction(() => action(item));
}

async function confirmLeave(reason) {
  const item = pendingLeave.value;
  pendingLeave.value = null;
  if (!item) return;
  await runAction(() => api.leave(item.number, reason));
}

async function confirmDelete() {
  const item = pendingDelete.value;
  pendingDelete.value = null;
  if (!item) return;
  await runAction(() => api.destroy(item.number));
}

onMounted(() => {
  bootstrap();
  ageTimer = window.setInterval(() => {
    now.value = Date.now();
  }, OPEN_AGE_TICK_MS);
});
onBeforeUnmount(() => {
  if (searchTimer) window.clearTimeout(searchTimer);
  if (ageTimer) window.clearInterval(ageTimer);
  closeContextMenu();
});
</script>

<template>
  <section class="page-list">
    <header class="page-header">
      <div>
        <h1 class="page-title">{{ filters.trashed ? 'Lixeira' : 'Chamados' }}</h1>
      </div>
    </header>

    <div class="toolbar">
      <label class="field">
        <span>Usuários</span>
        <SelectDropdown v-model="filters.user_id" :options="userOptions" @update:model-value="changeUser" />
      </label>
      <label class="field field-search">
        <span>Busca</span>
        <input v-model="filters.q" placeholder="Número, resumo..." @keydown.enter.prevent="searchNow" />
      </label>
      <FilterPopover :active="hasExtraFilters">
        <label class="field">
          <span>Status</span>
          <SelectDropdown
            v-model="filters.status"
            multiple
            placeholder="Todos"
            :options="statusOptions"
            @update:model-value="changeStatus"
          />
        </label>
        <label class="field">
          <span>Prioridade</span>
          <SelectDropdown
            v-model="filters.priority"
            multiple
            placeholder="Todas"
            :options="priorityOptions"
            @update:model-value="changeStatus"
          />
        </label>
        <label class="field">
          <span>Ordem</span>
          <SelectDropdown v-model="filters.sort" :options="sortOptions" @update:model-value="load" />
        </label>
        <label v-if="isAdmin" class="field field-check">
          <span>Lixeira</span>
          <input type="checkbox" v-model="filters.trashed" @change="changeTrash" />
        </label>
      </FilterPopover>
    </div>

    <p v-if="error" class="error">{{ error }}</p>

    <div class="page-list-body">
    <div v-if="!data.items.length" class="card empty">
      <p>{{ emptyMessage }}</p>
    </div>

    <div v-else class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Número</th>
            <th class="col-resumo">Resumo</th>
            <th class="col-status">Status</th>
            <th>Prioridade</th>
            <th>Prazo</th>
            <th>Participantes</th>
            <th>Criador</th>
            <th>Aberto</th>
            <th>Última modificação</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="item in data.items"
            :key="item.number"
            class="clickable"
            :class="{ 'context-open': contextMenu.open && contextMenu.item?.number === item.number }"
            @click="router.push({ name: 'dossie', params: { number: item.number } })"
            @contextmenu="openContextMenu($event, item)"
          >
            <td class="cell-nowrap">{{ item.number }}</td>
            <td class="cell-resumo" :title="item.subject || ''">{{ item.subject || '—' }}</td>
            <td class="cell-nowrap"><span class="pill" :class="item.status">{{ statusLabel(item.status) }}</span></td>
            <td class="cell-nowrap">
              <span v-if="item.priority" class="pill" :class="`priority-${item.priority}`">
                {{ priorityLabel(item.priority) }}
              </span>
              <span v-else class="muted">—</span>
            </td>
            <td class="muted cell-nowrap">{{ formatDueOn(item.due_on) }}</td>
            <td class="cell-names">
              <NamesOverflow :items="participanteNames(item)" />
            </td>
            <td class="cell-names" :title="creatorName(item)">{{ creatorName(item) }}</td>
            <td class="muted cell-nowrap">{{ openAgeLabel(item) }}</td>
            <td class="muted cell-nowrap">{{ new Date(item.updated_at).toLocaleString('pt-BR') }}</td>
          </tr>
        </tbody>
      </table>
    </div>
    </div>

    <div class="pagination">
      <div class="pagination-info">
        <span>Mostrando {{ rangeStart }}-{{ rangeEnd }} de {{ data.total }} itens</span>
        <label class="pagination-size">
          Itens por página:
          <SelectDropdown
            v-model="filters.per_page"
            compact
            :options="pageSizeOptions"
            @update:model-value="changePageSize"
          />
        </label>
      </div>
      <div class="pagination-nav">
        <button class="page-btn" type="button" :disabled="data.page <= 1" aria-label="Primeira página" @click="goToPage(1)">
          &lt;&lt;
        </button>
        <button class="page-btn" type="button" :disabled="data.page <= 1" aria-label="Página anterior" @click="goToPage(data.page - 1)">
          &lt;
        </button>
        <template v-for="(item, index) in pageItems" :key="`${item}-${index}`">
          <span v-if="item === '…'" class="page-ellipsis">…</span>
          <button
            v-else
            class="page-btn"
            :class="{ active: item === data.page }"
            type="button"
            @click="goToPage(item)"
          >
            {{ item }}
          </button>
        </template>
        <button
          class="page-btn"
          type="button"
          :disabled="data.page >= totalPages"
          aria-label="Próxima página"
          @click="goToPage(data.page + 1)"
        >
          &gt;
        </button>
        <button
          class="page-btn"
          type="button"
          :disabled="data.page >= totalPages"
          aria-label="Última página"
          @click="goToPage(totalPages)"
        >
          &gt;&gt;
        </button>
      </div>
    </div>
    <ContextMenu
      :open="contextMenu.open"
      :x="contextMenu.x"
      :y="contextMenu.y"
      :items="menuItems"
      @close="closeContextMenu"
      @select="onMenuSelect"
    />
    <ConfirmDialog
      :open="!!pendingDelete"
      title="Apagar chamado"
      :description="pendingDelete ? `Tem certeza que deseja apagar ${pendingDelete.number}? Ele some da lista e pode ser restaurado pela lixeira.` : ''"
      confirm-label="Apagar"
      danger
      @cancel="pendingDelete = null"
      @confirm="confirmDelete"
    />
    <ReasonDialog
      :open="!!pendingLeave"
      title="Abandonar atendimento"
      description="Informe o motivo para sair deste chamado."
      confirm-label="Abandonar"
      danger
      @cancel="pendingLeave = null"
      @confirm="confirmLeave"
    />
  </section>
</template>
