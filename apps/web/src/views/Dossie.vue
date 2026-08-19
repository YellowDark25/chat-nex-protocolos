<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AttachmentPreview from '../components/AttachmentPreview.vue';
import CommentsChat from '../components/CommentsChat.vue';
import ConfirmDialog from '../components/ConfirmDialog.vue';
import ReasonDialog from '../components/ReasonDialog.vue';
import SelectDropdown from '../components/SelectDropdown.vue';
import { api } from '../api.js';
import { openInChatwoot } from '../embed.js';
import { priorityLabel } from '../priority.js';
import { STATUS_LABELS } from '../status.js';
import { formatTimelineEvent } from '../timeline.js';

const STATUSES_REQUIRING_REASON = ['cancelado'];
const statusChoices = Object.entries(STATUS_LABELS).map(([value, label]) => ({ value, label }));

const props = defineProps({ number: { type: String, required: true } });
const route = useRoute();
const router = useRouter();
const item = ref(null);
const error = ref('');
const conversationQuery = ref('');
const contactId = ref('');
const session = ref(null);
const previewFile = ref(null);
const activeTab = ref('informacoes');
const reasonDialog = ref({
  open: false,
  title: '',
  description: '',
  confirmLabel: 'Confirmar',
  danger: false,
  pending: null
});
const deleteDialogOpen = ref(false);

const users = ref([]);
const accountId = computed(() => api.accountId());
const iAmParticipante = computed(() => memberIncludes(item.value?.participantes, session.value?.user?.id));
const iWatch = computed(() => memberIncludes(item.value?.watchers, session.value?.user?.id));
const openedByName = computed(() => {
  const openerId = item.value?.opened_by?.id ?? item.value?.opened_by_user_id;
  return lookupUserName(openerId, [item.value?.opened_by]);
});
const isAdmin = computed(() => {
  const account = session.value?.accounts?.find((acc) => String(acc.id) === String(accountId.value));
  return account?.role === 'administrator';
});
const isDeleted = computed(() => Boolean(item.value?.deleted_at));
const timelineEvents = computed(() =>
  (item.value?.events || []).map((event) => ({ id: event.id, ...formatTimelineEvent(event) }))
);

async function load() {
  error.value = '';
  try {
    const [sessionData, usersPayload] = await Promise.all([
      api.session(),
      api.users().catch((err) => {
        console.warn('Não foi possível listar usuários da conta', err);
        return { items: [] };
      })
    ]);
    session.value = sessionData;
    users.value = Array.isArray(usersPayload.items) ? usersPayload.items : [];
    item.value = await api.show(props.number || route.params.number);
  } catch (err) {
    error.value = err.message;
  }
}

async function run(action) {
  error.value = '';
  try {
    await action();
    await load();
  } catch (err) {
    error.value = err.message;
  }
}

function openReasonDialog(config) {
  reasonDialog.value = { open: true, ...config };
}

function closeReasonDialog() {
  reasonDialog.value = { ...reasonDialog.value, open: false, pending: null };
}

async function changeStatus(status) {
  if (!item.value || status === item.value.status) return;
  if (!STATUSES_REQUIRING_REASON.includes(status)) {
    await run(() => api.update(item.value.number, { status, reason: '' }));
    return;
  }
  openReasonDialog({
    title: 'Alterar status',
    description: 'Informe o motivo para cancelar este chamado.',
    confirmLabel: 'Salvar status',
    danger: false,
    pending: { type: 'status', status }
  });
}

function leaveProtocol() {
  openReasonDialog({
    title: 'Abandonar atendimento',
    description: 'Informe o motivo para sair deste chamado.',
    confirmLabel: 'Abandonar',
    danger: true,
    pending: { type: 'leave' }
  });
}

async function confirmDelete() {
  if (!item.value) return;
  deleteDialogOpen.value = false;
  error.value = '';
  try {
    await api.destroy(item.value.number);
    router.push({ name: 'lista' });
  } catch (err) {
    error.value = err.message;
  }
}

async function restoreChamado() {
  if (!item.value) return;
  await run(() => api.restore(item.value.number));
}

async function confirmReason(reason) {
  const pending = reasonDialog.value.pending;
  closeReasonDialog();
  if (!pending || !item.value) return;
  if (pending.type === 'leave') {
    await run(() => api.leave(item.value.number, reason));
    return;
  }
  if (pending.type === 'status') {
    await run(() => api.update(item.value.number, { status: pending.status, reason }));
  }
}

function conversationUrl(displayId) {
  return `/app/accounts/${accountId.value}/conversations/${displayId}`;
}

function contactUrl(contactId) {
  return `/app/accounts/${accountId.value}/contacts/${contactId}`;
}

function contactLabel(contact) {
  return contact.name || `#${contact.id}`;
}

function memberIncludes(members, userId) {
  return (members || []).some((member) => String(member.id ?? member) === String(userId));
}

function isPlaceholderName(name) {
  return !name || /^#\d+$/.test(String(name));
}

function lookupUserName(userId, hints = []) {
  if (!userId) return '—';
  const candidates = [...hints, session.value?.user, ...users.value];
  const match = candidates.find(
    (user) => user && String(user.id) === String(userId) && !isPlaceholderName(user.name)
  );
  return match?.name || `#${userId}`;
}

function memberName(member) {
  return lookupUserName(member?.id, [member]);
}

function memberNames(members) {
  if (!members?.length) return 'Nenhum';
  return members.map((member) => memberName(member)).join(', ');
}

onMounted(load);
</script>

<template>
  <section v-if="item" class="page-dossie" :class="{ 'page-dossie-chat': activeTab === 'comentarios' }">
    <router-link class="back" to="/">← Voltar para a lista</router-link>
    <header class="page-header">
      <div>
        <h1 class="page-title">{{ item.number }}</h1>
        <p class="page-subtitle">{{ item.subject || 'Sem resumo' }}</p>
      </div>
      <div class="header-actions">
        <template v-if="!isDeleted">
          <button v-if="!iAmParticipante" class="btn primary" type="button" @click="run(() => api.assume(item.number))">
            Assumir
          </button>
          <button v-if="!iWatch" class="btn" type="button" @click="run(() => api.watch(item.number))">Observar</button>
          <button v-else class="btn" type="button" @click="run(() => api.unwatch(item.number))">Parar de observar</button>
          <button v-if="iAmParticipante" class="btn danger" type="button" @click="leaveProtocol">Abandonar</button>
          <button
            v-if="isAdmin"
            class="btn danger"
            type="button"
            @click="deleteDialogOpen = true"
          >
            Apagar
          </button>
          <SelectDropdown
            class="status-select"
            :class="item.status"
            :model-value="item.status"
            :options="statusChoices"
            @update:model-value="changeStatus"
          />
        </template>
        <button v-else-if="isAdmin" class="btn primary" type="button" @click="restoreChamado">
          Restaurar
        </button>
      </div>
    </header>

    <div class="meta">
      <span class="pill" :class="item.priority ? `priority-${item.priority}` : ''">
        Prioridade: {{ priorityLabel(item.priority) }}
      </span>
      <span class="pill">Prazo: {{ item.due_on || '—' }}</span>
      <span class="pill">Abriu: {{ openedByName }}</span>
    </div>

    <p v-if="isDeleted" class="notice">Este chamado está na lixeira.</p>
    <p v-if="error" class="error">{{ error }}</p>

    <nav class="tabs" aria-label="Seções do chamado">
      <button
        class="tab"
        type="button"
        :class="{ active: activeTab === 'informacoes' }"
        @click="activeTab = 'informacoes'"
      >
        Informações
      </button>
      <button
        class="tab"
        type="button"
        :class="{ active: activeTab === 'comentarios' }"
        @click="activeTab = 'comentarios'"
      >
        Comentários
      </button>
    </nav>

    <div v-show="activeTab === 'informacoes'">
    <div v-if="item.assunto" class="card">
      <h3>Assunto</h3>
      <p class="assunto-body">{{ item.assunto }}</p>
    </div>

    <div class="card">
      <h3>Participantes</h3>
      <p>{{ memberNames(item.participantes) }}</p>
      <h3>Observadores</h3>
      <p class="muted">{{ memberNames(item.watchers) }}</p>
    </div>

    <div class="card">
      <h3>Conversas</h3>
      <ul class="list">
        <li v-for="conv in item.conversations" :key="conv.conversation_id">
          <a
            v-if="!conv.removed"
            :href="conversationUrl(conv.display_id)"
            @click.prevent="openInChatwoot(conversationUrl(conv.display_id))"
          >
            #{{ conv.display_id }} {{ conv.is_origin ? '(origem)' : '' }}
          </a>
          <span v-else class="muted">#{{ conv.display_id }} removida</span>
          <button
            v-if="!isDeleted"
            class="btn"
            type="button"
            @click="run(() => api.unlinkConversation(item.number, conv.conversation_id))"
          >
            Desvincular
          </button>
        </li>
      </ul>
      <div v-if="!isDeleted" class="row">
        <input v-model="conversationQuery" class="input" placeholder="Vincular conversa (# ou busca)" />
        <button class="btn" type="button" @click="run(() => api.linkConversation(item.number, conversationQuery))">
          Vincular
        </button>
      </div>
    </div>

    <div class="card">
      <h3>Contatos</h3>
      <ul class="list">
        <li v-for="contact in item.contacts" :key="contact.id">
          <a
            :href="contactUrl(contact.id)"
            @click.prevent="openInChatwoot(contactUrl(contact.id))"
          >
            {{ contactLabel(contact) }}
          </a>
          <button
            v-if="!isDeleted"
            class="btn"
            type="button"
            @click="run(() => api.unlinkContact(item.number, contact.id))"
          >
            Desvincular
          </button>
        </li>
      </ul>
      <div v-if="!isDeleted" class="row">
        <input v-model="contactId" class="input" placeholder="ID do contato" />
        <button class="btn" type="button" @click="run(() => api.linkContact(item.number, contactId))">
          Vincular contato
        </button>
      </div>
    </div>

    <div class="card">
      <h3>Anexos</h3>
      <ul class="list">
        <li v-for="file in item.attachments" :key="file.id">
          <button class="attachment-link" type="button" @click="previewFile = file">
            {{ file.filename }}
          </button>
        </li>
      </ul>
      <input v-if="!isDeleted" type="file" @change="run(() => api.attach(item.number, $event.target.files[0]))" />
    </div>

    <div class="card">
      <h3>Linha do tempo</h3>
      <div v-if="timelineEvents.length" class="timeline-scroll">
        <ol class="timeline">
          <li v-for="event in timelineEvents" :key="event.id" class="timeline-item">
            <div class="timeline-dot" aria-hidden="true" />
            <div>
              <p class="timeline-title">{{ event.title }}</p>
              <p v-if="event.detail" class="timeline-detail">{{ event.detail }}</p>
              <p class="muted timeline-time">{{ event.at }}</p>
            </div>
          </li>
        </ol>
      </div>
      <p v-else class="muted">Nenhum evento ainda.</p>
    </div>
    </div>

    <CommentsChat
      v-if="activeTab === 'comentarios'"
      :number="item.number"
      :current-user-id="session?.user?.id"
      :readonly="isDeleted"
    />

    <AttachmentPreview
      :open="!!previewFile"
      :number="item.number"
      :file="previewFile"
      @close="previewFile = null"
    />
    <ConfirmDialog
      :open="deleteDialogOpen"
      title="Apagar chamado"
      :description="`Tem certeza que deseja apagar ${item.number}? Ele some da lista e pode ser restaurado pela lixeira.`"
      confirm-label="Apagar"
      danger
      @cancel="deleteDialogOpen = false"
      @confirm="confirmDelete"
    />
    <ReasonDialog
      :open="reasonDialog.open"
      :title="reasonDialog.title"
      :description="reasonDialog.description"
      :confirm-label="reasonDialog.confirmLabel"
      :danger="reasonDialog.danger"
      @cancel="closeReasonDialog"
      @confirm="confirmReason"
    />
  </section>
  <p v-else-if="error" class="error">{{ error }}</p>
  <p v-else class="muted">Carregando…</p>
</template>
