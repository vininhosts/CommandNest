const DEFAULT_SYSTEM_PROMPT = 'You are a concise, helpful desktop AI assistant.';
const FREE_ROUTER_MODEL = 'openrouter/free';

const state = {
  settings: null,
  messages: [],
  currentRoute: 'assistant',
  isSending: false,
  activeRequestId: null,
  activeAssistantId: null,
  activeParser: null,
  agentActivity: []
};

const dom = {
  assistantView: document.getElementById('assistantView'),
  settingsView: document.getElementById('settingsView'),
  conversation: document.getElementById('conversation'),
  activity: document.getElementById('activity'),
  prompt: document.getElementById('prompt'),
  status: document.getElementById('status'),
  sendButton: document.getElementById('sendButton'),
  copyButton: document.getElementById('copyButton'),
  clearButton: document.getElementById('clearButton'),
  settingsButton: document.getElementById('settingsButton'),
  closeButton: document.getElementById('closeButton'),
  modelPicker: document.getElementById('modelPicker'),
  settingsModelPicker: document.getElementById('settingsModelPicker'),
  apiKey: document.getElementById('apiKey'),
  secureStorageNote: document.getElementById('secureStorageNote'),
  modelList: document.getElementById('modelList'),
  systemPrompt: document.getElementById('systemPrompt'),
  agentMode: document.getElementById('agentMode'),
  confirmActions: document.getElementById('confirmActions'),
  launchAtLogin: document.getElementById('launchAtLogin'),
  shortcut: document.getElementById('shortcut'),
  settingsStatus: document.getElementById('settingsStatus'),
  refreshModelsButton: document.getElementById('refreshModelsButton'),
  saveSettingsButton: document.getElementById('saveSettingsButton')
};

class ReasoningParser {
  constructor() {
    this.buffer = '';
    this.isInsideReasoning = false;
    this.retainedTailLength = 24;
  }

  consume(text) {
    if (!text) {
      return { answer: '', reasoning: '' };
    }
    this.buffer += text;
    return this.drain(true);
  }

  finish() {
    return this.drain(false);
  }

  drain(keepTail) {
    const result = { answer: '', reasoning: '' };
    while (this.buffer.length) {
      if (this.isInsideReasoning) {
        const close = this.firstTag(['</think>', '</thinking>']);
        if (close) {
          result.reasoning += this.buffer.slice(0, close.start);
          this.buffer = this.buffer.slice(close.end);
          this.isInsideReasoning = false;
          continue;
        }
        const drained = this.drainablePrefix(keepTail);
        result.reasoning += drained;
        if (!drained) {
          break;
        }
      } else {
        const open = this.firstTag(['<think>', '<thinking>']);
        if (open) {
          result.answer += this.buffer.slice(0, open.start);
          this.buffer = this.buffer.slice(open.end);
          this.isInsideReasoning = true;
          continue;
        }
        const drained = this.drainablePrefix(keepTail);
        result.answer += drained;
        if (!drained) {
          break;
        }
      }
    }
    return result;
  }

  firstTag(tags) {
    const lower = this.buffer.toLowerCase();
    return tags
      .map((tag) => {
        const start = lower.indexOf(tag);
        return start >= 0 ? { start, end: start + tag.length } : null;
      })
      .filter(Boolean)
      .sort((a, b) => a.start - b.start)[0] || null;
  }

  drainablePrefix(keepTail) {
    if (!keepTail) {
      const drained = this.buffer;
      this.buffer = '';
      return drained;
    }
    if (this.buffer.length <= this.retainedTailLength) {
      return '';
    }
    const split = this.buffer.length - this.retainedTailLength;
    const drained = this.buffer.slice(0, split);
    this.buffer = this.buffer.slice(split);
    return drained;
  }
}

function escapeHTML(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderInlineMarkdown(text) {
  return escapeHTML(text)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/\*([^*]+)\*/g, '<em>$1</em>')
    .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, '<a href="$2">$1</a>');
}

function renderMarkdown(text) {
  const parts = [];
  let rest = String(text || '');
  const fencePattern = /```([a-zA-Z0-9_-]*)?\n([\s\S]*?)```/m;

  while (rest.length) {
    const match = rest.match(fencePattern);
    if (!match) {
      parts.push(renderParagraphs(rest));
      break;
    }
    parts.push(renderParagraphs(rest.slice(0, match.index)));
    parts.push(`<pre><code>${escapeHTML(match[2])}</code></pre>`);
    rest = rest.slice(match.index + match[0].length);
  }

  return parts.join('');
}

function renderParagraphs(text) {
  return String(text || '')
    .trim()
    .split(/\n{2,}/)
    .filter(Boolean)
    .map((paragraph) => `<p>${renderInlineMarkdown(paragraph).replace(/\n/g, '<br />')}</p>`)
    .join('');
}

function visibleMessages() {
  return state.messages.filter((message) => message.role !== 'system');
}

function lastAssistantResponse() {
  const last = [...state.messages].reverse().find((message) => message.role === 'assistant');
  return last?.content || '';
}

function renderConversation() {
  const messages = visibleMessages();
  if (!messages.length) {
    const shortcut = state.settings?.shortcut || state.settings?.defaultShortcut || 'Alt+Space';
    dom.conversation.innerHTML = `<div class="empty"><div><strong>Ask anything</strong><br />${escapeHTML(shortcut)} opens this assistant from anywhere.</div></div>`;
    return;
  }

  dom.conversation.innerHTML = `<div class="messages">${messages.map(renderMessage).join('')}</div>`;
  dom.conversation.scrollTop = dom.conversation.scrollHeight;
}

function renderMessage(message) {
  const content = message.content || 'Thinking...';
  const thinking = message.role === 'assistant' && message.reasoning
    ? `<details class="thinking"><summary>Thinking</summary><div>${renderMarkdown(message.reasoning)}</div></details>`
    : '';
  return `
    <div class="message-row ${message.role}">
      <div class="bubble">
        ${thinking}
        ${renderMarkdown(content)}
      </div>
    </div>
  `;
}

function renderActivity() {
  if (!state.agentActivity.length) {
    dom.activity.classList.add('hidden');
    dom.activity.innerHTML = '';
    return;
  }
  dom.activity.classList.remove('hidden');
  dom.activity.innerHTML = state.agentActivity.slice(-5).map((event) => `<div>${escapeHTML(event)}</div>`).join('');
}

function setStatus(message, isError = false) {
  dom.status.textContent = message;
  dom.status.classList.toggle('error', isError);
}

function routeTo(route) {
  state.currentRoute = route;
  dom.assistantView.classList.toggle('active', route === 'assistant');
  dom.settingsView.classList.toggle('active', route === 'settings');
  if (route === 'assistant') {
    setTimeout(() => dom.prompt.focus(), 40);
  }
}

function renderModelPicker(container, getModels, getSelected, setSelected) {
  container.innerHTML = `
    <button class="model-button" type="button">
      <span>${escapeHTML(getSelected() || 'Select model')}</span>
      <strong>Search</strong>
    </button>
    <div class="model-popover hidden">
      <input class="model-search" type="text" placeholder="Search models" />
      <div class="model-results"></div>
    </div>
  `;

  const button = container.querySelector('.model-button');
  const popover = container.querySelector('.model-popover');
  const search = container.querySelector('.model-search');
  const results = container.querySelector('.model-results');

  function renderResults() {
    const query = search.value.trim().toLowerCase();
    const models = getModels().filter((model) => !query || model.toLowerCase().includes(query));
    results.innerHTML = models.length
      ? models.map((model) => `
          <button type="button" class="model-option ${model === getSelected() ? 'active' : ''}" data-model="${escapeHTML(model)}">
            <span>${model === getSelected() ? '●' : '○'}</span>
            <span>${escapeHTML(model)}</span>
          </button>
        `).join('')
      : '<div class="empty">No matching models</div>';

    results.querySelectorAll('.model-option').forEach((option) => {
      option.addEventListener('click', () => {
        setSelected(option.dataset.model);
        popover.classList.add('hidden');
        renderAll();
      });
    });
  }

  button.addEventListener('click', () => {
    const rect = button.getBoundingClientRect();
    popover.style.top = `${Math.min(rect.bottom + 6, window.innerHeight - 350)}px`;
    popover.style.left = `${Math.min(rect.left, window.innerWidth - 448)}px`;
    search.value = '';
    renderResults();
    popover.classList.toggle('hidden');
    setTimeout(() => search.focus(), 20);
  });

  search.addEventListener('input', renderResults);
}

function renderAll() {
  if (!state.settings) {
    return;
  }

  renderModelPicker(
    dom.modelPicker,
    () => state.settings.modelIDs,
    () => state.settings.selectedModelID,
    (model) => {
      state.settings.selectedModelID = model;
      window.commandNest.saveSettings({ ...state.settings, apiKey: dom.apiKey.value || '********' }).catch(() => {});
    }
  );
  renderModelPicker(
    dom.settingsModelPicker,
    () => normalizedModels(dom.modelList.value.split(/\n/)),
    () => state.settings.selectedModelID,
    (model) => {
      state.settings.selectedModelID = model;
    }
  );
  renderConversation();
  renderActivity();
  dom.sendButton.disabled = state.isSending || !dom.prompt.value.trim();
  dom.copyButton.disabled = !lastAssistantResponse();
}

function normalizedModels(models) {
  const seen = new Set();
  return [FREE_ROUTER_MODEL, ...models]
    .flatMap((model) => String(model || '').split(/[,\n]/))
    .map((model) => model.trim())
    .filter(Boolean)
    .filter((model) => {
      if (seen.has(model)) {
        return false;
      }
      seen.add(model);
      return true;
    });
}

function syncSettingsForm() {
  dom.apiKey.value = state.settings.apiKey || '';
  dom.secureStorageNote.textContent = state.settings.secureStorageAvailable
    ? 'Stored with OS secure storage.'
    : 'Secure storage is unavailable. Use an OS keyring or OPENROUTER_API_KEY for development.';
  dom.modelList.value = state.settings.modelIDs.join('\n');
  dom.systemPrompt.value = state.settings.systemPrompt || DEFAULT_SYSTEM_PROMPT;
  dom.agentMode.checked = Boolean(state.settings.agentModeEnabled);
  dom.confirmActions.checked = Boolean(state.settings.confirmAgentActions);
  dom.launchAtLogin.checked = Boolean(state.settings.launchAtLogin);
  dom.shortcut.placeholder = state.settings.defaultShortcut || 'Alt+Space';
  dom.shortcut.value = state.settings.shortcut || state.settings.defaultShortcut || 'Alt+Space';
}

async function saveSettings() {
  dom.settingsStatus.textContent = '';
  dom.settingsStatus.classList.remove('error');
  const modelIDs = normalizedModels(dom.modelList.value.split(/\n/));
  try {
    state.settings = await window.commandNest.saveSettings({
      ...state.settings,
      apiKey: dom.apiKey.value,
      modelIDs,
      selectedModelID: modelIDs.includes(state.settings.selectedModelID) ? state.settings.selectedModelID : modelIDs[0],
      systemPrompt: dom.systemPrompt.value,
      agentModeEnabled: dom.agentMode.checked,
      confirmAgentActions: dom.confirmActions.checked,
      launchAtLogin: dom.launchAtLogin.checked,
      shortcut: dom.shortcut.value
    });
    syncSettingsForm();
    renderAll();
    dom.settingsStatus.textContent = 'Settings saved.';
  } catch (error) {
    dom.settingsStatus.textContent = error.message;
    dom.settingsStatus.classList.add('error');
  }
}

async function refreshModels() {
  dom.settingsStatus.textContent = 'Loading models...';
  dom.settingsStatus.classList.remove('error');
  dom.refreshModelsButton.disabled = true;
  try {
    const models = await window.commandNest.refreshModels();
    dom.modelList.value = models.join('\n');
    state.settings.modelIDs = models;
    if (!models.includes(state.settings.selectedModelID)) {
      state.settings.selectedModelID = FREE_ROUTER_MODEL;
    }
    renderAll();
    dom.settingsStatus.textContent = `Loaded ${models.length} models.`;
  } catch (error) {
    dom.settingsStatus.textContent = error.message;
    dom.settingsStatus.classList.add('error');
  } finally {
    dom.refreshModelsButton.disabled = false;
  }
}

function appendAssistantChunk(payload) {
  if (payload.requestId !== state.activeRequestId) {
    return;
  }

  const message = state.messages.find((item) => item.id === state.activeAssistantId);
  if (!message) {
    return;
  }

  if (payload.reasoning) {
    message.reasoning += payload.reasoning;
  }

  const parsed = state.activeParser.consume(payload.content || '');
  message.content += parsed.answer;
  message.reasoning += parsed.reasoning;
  renderConversation();
}

function finishAssistant(payload, preserveStatus = false) {
  if (payload.requestId !== state.activeRequestId) {
    return;
  }

  const message = state.messages.find((item) => item.id === state.activeAssistantId);
  if (message && state.activeParser) {
    const tail = state.activeParser.finish();
    message.content += tail.answer;
    message.reasoning += tail.reasoning;
  }

  state.isSending = false;
  state.activeRequestId = null;
  state.activeAssistantId = null;
  state.activeParser = null;
  if (!preserveStatus) {
    setStatus('Enter sends. Shift + Enter adds a line.');
  }
  renderAll();
}

async function sendPrompt() {
  const text = dom.prompt.value.trim();
  if (!text || state.isSending) {
    return;
  }

  const userMessage = { id: crypto.randomUUID(), role: 'user', content: text, reasoning: '' };
  const assistantMessage = { id: crypto.randomUUID(), role: 'assistant', content: '', reasoning: '' };
  state.messages.push(userMessage, assistantMessage);
  state.agentActivity = [];
  state.isSending = true;
  state.activeRequestId = crypto.randomUUID();
  state.activeAssistantId = assistantMessage.id;
  state.activeParser = new ReasoningParser();
  dom.prompt.value = '';
  setStatus('Streaming');
  renderAll();

  const requestMessages = [
    { role: 'system', content: state.settings.systemPrompt || DEFAULT_SYSTEM_PROMPT },
    ...state.messages
      .filter((message) => message.id !== assistantMessage.id)
      .map((message) => ({ role: message.role, content: message.content }))
  ];

  try {
    await window.commandNest.sendPrompt({
      requestId: state.activeRequestId,
      model: state.settings.selectedModelID,
      messages: requestMessages
    });
  } catch (error) {
    state.isSending = false;
    state.activeParser = null;
    state.messages = state.messages.filter((message) => message.id !== assistantMessage.id || message.content.trim());
    setStatus(error.message, true);
    renderAll();
  }
}

function clearConversation() {
  state.messages = [];
  state.agentActivity = [];
  state.isSending = false;
  state.activeRequestId = null;
  state.activeAssistantId = null;
  state.activeParser = null;
  setStatus('Enter sends. Shift + Enter adds a line.');
  renderAll();
}

async function boot() {
  state.settings = await window.commandNest.getSettings();
  syncSettingsForm();
  renderAll();

  window.commandNest.onNavigate(routeTo);
  window.commandNest.onSettingsUpdated((settings) => {
    state.settings = settings;
    syncSettingsForm();
    renderAll();
  });
  window.commandNest.onAssistantChunk(appendAssistantChunk);
  window.commandNest.onAssistantDone(finishAssistant);
  window.commandNest.onAssistantError((payload) => {
    finishAssistant(payload, true);
    setStatus(payload.message, true);
  });
  window.commandNest.onAssistantActivity((payload) => {
    if (payload.requestId !== state.activeRequestId) {
      return;
    }
    state.agentActivity.push(payload.event);
    renderActivity();
  });
}

dom.sendButton.addEventListener('click', sendPrompt);
dom.prompt.addEventListener('input', renderAll);
dom.prompt.addEventListener('keydown', (event) => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    sendPrompt();
  }
});
dom.settingsButton.addEventListener('click', () => routeTo('settings'));
dom.closeButton.addEventListener('click', () => window.commandNest.closeWindow());
dom.clearButton.addEventListener('click', clearConversation);
dom.copyButton.addEventListener('click', () => window.commandNest.copyText(lastAssistantResponse()));
dom.saveSettingsButton.addEventListener('click', saveSettings);
dom.refreshModelsButton.addEventListener('click', refreshModels);
dom.modelList.addEventListener('input', renderAll);
document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') {
    window.commandNest.closeWindow();
  }
});
document.addEventListener('click', (event) => {
  document.querySelectorAll('.model-picker').forEach((picker) => {
    if (!picker.contains(event.target)) {
      picker.querySelector('.model-popover')?.classList.add('hidden');
    }
  });
});

boot().catch((error) => {
  setStatus(error.message, true);
});
