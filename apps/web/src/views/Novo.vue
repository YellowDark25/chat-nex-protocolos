<script setup>
import { onMounted, reactive, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import DictationButton from '../components/DictationButton.vue';
import SelectDropdown from '../components/SelectDropdown.vue';
import { api } from '../api.js';

const priorityOptions = [
  { value: '', label: 'Nenhuma' },
  { value: 'baixa', label: 'Baixa' },
  { value: 'media', label: 'Média' },
  { value: 'alta', label: 'Alta' }
];
const notifyOptions = [
  { value: 'none', label: 'Não enviar' },
  { value: 'chat', label: 'Mensagem no chat' },
  { value: 'note', label: 'Nota privada' }
];

const route = useRoute();
const router = useRouter();
const error = ref('');
const form = reactive({
  conversation_id: route.query.conversation_id || '',
  subject: '',
  assunto: '',
  priority: '',
  due_on: '',
  notify: 'none'
});

async function submit() {
  error.value = '';
  if (!form.assunto.trim()) {
    error.value = 'Assunto obrigatório';
    return;
  }
  try {
    const created = await api.create(form);
    router.replace({ name: 'dossie', params: { number: created.number } });
  } catch (err) {
    error.value = err.reload ? `${err.message} Recarregue a página.` : err.message;
  }
}

onMounted(() => {
  if (route.query.account_id) {
    sessionStorage.setItem('nex_account_id', String(route.query.account_id));
  }
});
</script>

<template>
  <section>
    <router-link class="back" to="/">← Voltar para a lista</router-link>
    <header class="page-header">
      <div>
        <h1 class="page-title">Abrir chamado</h1>
        <p class="page-subtitle">Gera o número e a ficha desta conversa</p>
      </div>
    </header>

    <div class="card form-card">
      <label class="field">
        <span>Conversa</span>
        <input v-model="form.conversation_id" placeholder="Número da conversa" />
      </label>
      <label class="field">
        <span>Resumo (opcional)</span>
        <input v-model="form.subject" placeholder="Resumo do caso" maxlength="255" />
        <span class="muted" style="align-self: flex-end; font-size: 12px">{{ form.subject.length }}/255</span>
      </label>
      <div class="field">
        <span class="field-heading">
          Assunto
          <DictationButton v-model="form.assunto" :max-length="2000" @error="error = $event" />
        </span>
        <textarea v-model="form.assunto" placeholder="Motivo da abertura do chamado" maxlength="2000" rows="4"></textarea>
        <span class="muted" style="align-self: flex-end; font-size: 12px">{{ form.assunto.length }}/2000</span>
      </div>
      <label class="field">
        <span>Prioridade</span>
        <SelectDropdown v-model="form.priority" :options="priorityOptions" />
      </label>
      <label class="field">
        <span>Prazo</span>
        <input v-model="form.due_on" type="date" />
      </label>
      <label class="field">
        <span>Avisar</span>
        <SelectDropdown v-model="form.notify" :options="notifyOptions" />
      </label>
      <p v-if="error" class="error">{{ error }}</p>
      <button class="btn primary" type="button" @click="submit">Criar e abrir chamado</button>
    </div>
  </section>
</template>
