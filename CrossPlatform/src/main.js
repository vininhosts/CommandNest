const { app, BrowserWindow, Menu, Tray, globalShortcut, ipcMain, dialog, shell, clipboard, safeStorage, nativeImage } = require('electron');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const APP_ID = 'io.github.vininhosts.CommandNest';
const APP_NAME = 'CommandNest';
const OPENROUTER_ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions';
const OPENROUTER_MODELS_ENDPOINT = 'https://openrouter.ai/api/v1/models';
const OPENROUTER_REFERER = 'https://github.com/vininhosts/CommandNest';
const OPENROUTER_TITLE = 'CommandNest';
const FREE_ROUTER_MODEL = 'openrouter/free';
const DEFAULT_SYSTEM_PROMPT = 'You are a concise, helpful desktop AI assistant.';
const DEFAULT_MODELS = [
  FREE_ROUTER_MODEL,
  'openai/gpt-4o-mini',
  'anthropic/claude-3.5-haiku',
  'google/gemini-flash-1.5',
  'meta-llama/llama-3.1-8b-instruct'
];

let assistantWindow;
let tray;
let currentShortcut = 'Alt+Space';

function userDataPath(fileName) {
  return path.join(app.getPath('userData'), fileName);
}

function defaultSettings() {
  return {
    modelIDs: DEFAULT_MODELS,
    selectedModelID: FREE_ROUTER_MODEL,
    systemPrompt: DEFAULT_SYSTEM_PROMPT,
    shortcut: 'Alt+Space',
    agentModeEnabled: true,
    confirmAgentActions: true,
    launchAtLogin: isLaunchAtLoginEnabled()
  };
}

function normalizeModels(models) {
  const seen = new Set();
  return [FREE_ROUTER_MODEL, ...models]
    .flatMap((model) => String(model || '').split(/[\n,]/))
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

function loadSettings() {
  try {
    const stored = JSON.parse(fs.readFileSync(userDataPath('settings.json'), 'utf8'));
    const merged = { ...defaultSettings(), ...stored };
    merged.modelIDs = normalizeModels(merged.modelIDs || DEFAULT_MODELS);
    if (!merged.modelIDs.includes(merged.selectedModelID)) {
      merged.selectedModelID = FREE_ROUTER_MODEL;
    }
    merged.launchAtLogin = isLaunchAtLoginEnabled();
    return merged;
  } catch {
    return defaultSettings();
  }
}

function saveSettings(settings) {
  const normalized = {
    ...loadSettings(),
    ...settings,
    modelIDs: normalizeModels(settings.modelIDs || DEFAULT_MODELS),
    systemPrompt: String(settings.systemPrompt || DEFAULT_SYSTEM_PROMPT).trim() || DEFAULT_SYSTEM_PROMPT,
    shortcut: String(settings.shortcut || 'Alt+Space').trim() || 'Alt+Space'
  };

  if (!normalized.modelIDs.includes(normalized.selectedModelID)) {
    normalized.selectedModelID = normalized.modelIDs[0] || FREE_ROUTER_MODEL;
  }

  setLaunchAtLogin(Boolean(normalized.launchAtLogin));
  fs.writeFileSync(userDataPath('settings.json'), JSON.stringify({ ...normalized, launchAtLogin: undefined }, null, 2));
  registerShortcut(normalized.shortcut);
  return loadSettings();
}

function apiKeyPath() {
  return userDataPath('openrouter-key.bin');
}

function loadAPIKey() {
  if (process.env.OPENROUTER_API_KEY) {
    return process.env.OPENROUTER_API_KEY.trim();
  }

  try {
    if (!safeStorage.isEncryptionAvailable()) {
      return '';
    }
    const encrypted = Buffer.from(fs.readFileSync(apiKeyPath(), 'utf8'), 'base64');
    return safeStorage.decryptString(encrypted);
  } catch {
    return '';
  }
}

function saveAPIKey(apiKey) {
  const trimmed = String(apiKey || '').trim();
  if (!trimmed) {
    try {
      fs.unlinkSync(apiKeyPath());
    } catch {
      // No saved key to remove.
    }
    return;
  }

  if (!safeStorage.isEncryptionAvailable()) {
    throw new Error('Secure storage is not available on this system. Configure the OS keyring or use OPENROUTER_API_KEY for development.');
  }

  fs.writeFileSync(apiKeyPath(), safeStorage.encryptString(trimmed).toString('base64'), { mode: 0o600 });
}

function quoteForDesktopFile(value) {
  return `"${String(value).replace(/"/g, '\\"')}"`;
}

function linuxAutostartPath() {
  return path.join(os.homedir(), '.config', 'autostart', `${APP_ID}.desktop`);
}

function linuxLaunchCommand() {
  if (app.isPackaged) {
    return quoteForDesktopFile(process.execPath);
  }

  return `${quoteForDesktopFile(process.execPath)} ${quoteForDesktopFile(path.resolve(__dirname, '..'))}`;
}

function isLaunchAtLoginEnabled() {
  if (process.platform === 'linux') {
    return fs.existsSync(linuxAutostartPath());
  }

  return app.getLoginItemSettings().openAtLogin;
}

function setLaunchAtLogin(enabled) {
  if (process.platform === 'linux') {
    const autostartFile = linuxAutostartPath();
    if (!enabled) {
      try {
        fs.unlinkSync(autostartFile);
      } catch {
        // Already disabled.
      }
      return;
    }

    fs.mkdirSync(path.dirname(autostartFile), { recursive: true });
    fs.writeFileSync(
      autostartFile,
      [
        '[Desktop Entry]',
        'Type=Application',
        `Name=${APP_NAME}`,
        `Exec=${linuxLaunchCommand()}`,
        'Terminal=false',
        'X-GNOME-Autostart-enabled=true'
      ].join('\n')
    );
    return;
  }

  app.setLoginItemSettings({ openAtLogin: enabled });
}

function createTrayIcon() {
  const svg = encodeURIComponent(`
    <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
      <rect width="32" height="32" rx="8" fill="#111827"/>
      <path d="M9 16h14M16 9v14" stroke="#f9fafb" stroke-width="3" stroke-linecap="round"/>
    </svg>
  `);
  return nativeImage.createFromDataURL(`data:image/svg+xml;charset=utf-8,${svg}`);
}

function createWindow() {
  assistantWindow = new BrowserWindow({
    width: 760,
    height: 600,
    minWidth: 680,
    minHeight: 520,
    show: false,
    frame: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    backgroundColor: '#00000000',
    title: APP_NAME,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  assistantWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  assistantWindow.on('blur', () => {
    if (!assistantWindow.webContents.isDevToolsOpened()) {
      assistantWindow.hide();
    }
  });
}

function showAssistant(route = 'assistant') {
  if (!assistantWindow) {
    createWindow();
  }

  assistantWindow.center();
  assistantWindow.show();
  assistantWindow.focus();
  assistantWindow.webContents.send('app:navigate', route);
}

function toggleAssistant() {
  if (!assistantWindow) {
    createWindow();
  }

  if (assistantWindow.isVisible()) {
    assistantWindow.hide();
  } else {
    showAssistant('assistant');
  }
}

function registerShortcut(shortcut) {
  globalShortcut.unregister(currentShortcut);
  const requested = shortcut || 'Alt+Space';
  const ok = globalShortcut.register(requested, toggleAssistant);
  currentShortcut = ok ? requested : 'Alt+Space';

  if (!ok && requested !== 'Alt+Space') {
    globalShortcut.register('Alt+Space', toggleAssistant);
  }
}

function createMenu() {
  if (tray) {
    tray.destroy();
  }

  const settings = loadSettings();
  tray = new Tray(createTrayIcon());
  tray.setToolTip(APP_NAME);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Show Assistant', click: () => showAssistant('assistant') },
    { label: 'Settings', click: () => showAssistant('settings') },
    { type: 'separator' },
    {
      label: 'Launch at Login',
      type: 'checkbox',
      checked: settings.launchAtLogin,
      click: (item) => {
        const updated = saveSettings({ ...loadSettings(), launchAtLogin: item.checked });
        assistantWindow?.webContents.send('settings:updated', settingsForRenderer(updated));
      }
    },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() }
  ]));
  tray.on('click', () => showAssistant('assistant'));
}

function settingsForRenderer(settings = loadSettings()) {
  return {
    ...settings,
    apiKey: loadAPIKey() ? '********' : '',
    secureStorageAvailable: safeStorage.isEncryptionAvailable()
  };
}

function headers(apiKey) {
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
    'HTTP-Referer': OPENROUTER_REFERER,
    'X-Title': OPENROUTER_TITLE
  };
}

async function responseError(response) {
  const text = await response.text().catch(() => '');
  let message = text;
  try {
    message = JSON.parse(text).error?.message || text;
  } catch {
    // Keep plain text response body.
  }

  if (response.status === 401 || response.status === 403) {
    return new Error(message || 'OpenRouter rejected the API key. Check it in Settings.');
  }
  if (response.status === 429) {
    return new Error(message || 'OpenRouter rate limited the request. Try again shortly.');
  }
  if ([400, 404, 422].includes(response.status)) {
    return new Error(message || 'OpenRouter could not use the selected model. Choose another model in Settings.');
  }

  return new Error(message || `OpenRouter returned HTTP ${response.status}.`);
}

async function fetchModels() {
  const response = await fetch(OPENROUTER_MODELS_ENDPOINT, {
    headers: {
      'HTTP-Referer': OPENROUTER_REFERER,
      'X-Title': OPENROUTER_TITLE
    }
  });

  if (!response.ok) {
    throw await responseError(response);
  }

  const json = await response.json();
  return normalizeModels((json.data || []).map((model) => model.id));
}

async function chatCompletion({ apiKey, model, messages, stream, tools }) {
  const body = {
    model,
    messages,
    stream,
    tools: tools?.length ? tools : undefined,
    tool_choice: tools?.length ? 'auto' : undefined
  };

  const response = await fetch(OPENROUTER_ENDPOINT, {
    method: 'POST',
    headers: headers(apiKey),
    body: JSON.stringify(body)
  });

  if (!response.ok) {
    throw await responseError(response);
  }

  return response;
}

function reasoningText(payload = {}) {
  return [payload.reasoning, payload.reasoning_content, payload.reasoning_text, payload.thinking]
    .map((value) => String(value || '').trim())
    .filter(Boolean)
    .join('\n\n');
}

async function* linesFromStream(stream) {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) {
      yield line;
    }
  }

  buffer += decoder.decode();
  if (buffer) {
    yield buffer;
  }
}

async function streamChat(sender, requestId, apiKey, model, messages) {
  let receivedChunk = false;

  try {
    const response = await chatCompletion({ apiKey, model, messages, stream: true });
    for await (const line of linesFromStream(response.body)) {
      const trimmed = line.trim();
      if (!trimmed.startsWith('data:')) {
        continue;
      }

      const payload = trimmed.slice(5).trim();
      if (payload === '[DONE]') {
        break;
      }

      const event = JSON.parse(payload);
      if (event.error?.message) {
        throw new Error(event.error.message);
      }

      for (const choice of event.choices || []) {
        const content = choice.delta?.content || '';
        const reasoning = reasoningText(choice.delta || {});
        if (content || reasoning) {
          receivedChunk = true;
          sender.send('assistant:chunk', { requestId, content, reasoning });
        }
      }
    }
  } catch (error) {
    if (receivedChunk) {
      sender.send('assistant:error', { requestId, message: `${error.message} Partial response was preserved.` });
      return;
    }

    const response = await completeChat(apiKey, model, messages);
    sender.send('assistant:chunk', { requestId, content: response.content, reasoning: response.reasoning });
  }

  sender.send('assistant:done', { requestId });
}

async function completeChat(apiKey, model, messages) {
  const response = await chatCompletion({ apiKey, model, messages, stream: false });
  const json = await response.json();
  if (json.error?.message) {
    throw new Error(json.error.message);
  }

  const message = json.choices?.[0]?.message || {};
  const content = message.content || '';
  const reasoning = reasoningText(message);
  if (!content && !reasoning) {
    throw new Error('OpenRouter returned an empty response.');
  }

  return { content, reasoning, toolCalls: message.tool_calls || [] };
}

function shouldUseLocalAgent(prompt) {
  const normalized = prompt.toLowerCase();
  const actionWords = ['create', 'make', 'write', 'edit', 'modify', 'change', 'organize', 'move', 'rename', 'delete', 'trash', 'copy', 'read', 'list', 'show', 'find', 'search', 'inspect', 'open', 'run', 'execute', 'install', 'build', 'test', 'fix', 'debug'];
  const targets = ['file', 'files', 'folder', 'folders', 'directory', 'directories', 'downloads', 'desktop', 'documents', 'project', 'app', 'code', 'terminal', 'command', 'script', 'repo', 'repository', '.js', '.ts', '.md', '.txt', '~/', '/users/', 'c:\\'];
  return normalized.includes('my computer')
    || normalized.includes('this computer')
    || normalized.includes('local machine')
    || (actionWords.some((word) => normalized.includes(word)) && targets.some((target) => normalized.includes(target)));
}

const toolDefinitions = [
  tool('list_directory', 'List files and folders in a directory.', { path: prop('Directory path') }, ['path']),
  tool('read_text_file', 'Read a text file.', { path: prop('File path'), max_bytes: prop('Maximum bytes to read', 'number') }, ['path']),
  tool('write_text_file', 'Create or overwrite a UTF-8 text file.', { path: prop('File path'), content: prop('Text content') }, ['path', 'content']),
  tool('create_directory', 'Create a directory.', { path: prop('Directory path') }, ['path']),
  tool('move_item', 'Move or rename a file or folder.', { source_path: prop('Source path'), destination_path: prop('Destination path') }, ['source_path', 'destination_path']),
  tool('copy_item', 'Copy a file or folder.', { source_path: prop('Source path'), destination_path: prop('Destination path') }, ['source_path', 'destination_path']),
  tool('trash_item', 'Move a file or folder to the Trash/Recycle Bin.', { path: prop('Path') }, ['path']),
  tool('run_shell_command', 'Run a shell command on the local machine.', { command: prop('Command to run') }, ['command']),
  tool('open_item', 'Open a file, folder, app, or URL.', { path: prop('Path or URL') }, ['path'])
];

function prop(description, type = 'string') {
  return { type, description };
}

function tool(name, description, properties, required) {
  return {
    type: 'function',
    function: {
      name,
      description,
      parameters: {
        type: 'object',
        properties,
        required,
        additionalProperties: false
      }
    }
  };
}

function agentSystemPrompt(message) {
  if (message.role !== 'system') {
    return message.content;
  }

  return `${message.content}

Local Agent Mode is enabled. You are an acting desktop and coding agent, not an advice bot. When the user asks you to create, edit, organize, inspect, move, rename, run, install, build, test, open, or otherwise change something on this computer, use tools to do it. Do not answer with generic instructions for tasks you can perform. Prefer the smallest effective action. Use absolute paths when possible. Destructive operations require user confirmation. After using tools, explain what you changed or found concisely.`;
}

async function runAgent(sender, requestId, apiKey, model, messages, settings) {
  const payloadMessages = messages.map((message) => ({ role: message.role, content: agentSystemPrompt(message) }));
  const needsLocalTools = shouldUseLocalAgent(messages.at(-1)?.content || '');
  let retriedMissingTools = false;
  sender.send('assistant:activity', { requestId, event: 'Starting local agent' });

  for (let round = 0; round < 8; round += 1) {
    const result = await completeChatWithTools(apiKey, model, payloadMessages);
    if (!result.toolCalls.length) {
      if (needsLocalTools && !retriedMissingTools) {
        retriedMissingTools = true;
        payloadMessages.push({ role: 'assistant', content: result.content });
        payloadMessages.push({ role: 'user', content: 'You answered with advice instead of acting. Execute the request now using the local tools. If a permission blocks you, report the specific permission or path.' });
        continue;
      }
      sender.send('assistant:chunk', { requestId, content: result.content || 'Done.', reasoning: result.reasoning });
      sender.send('assistant:done', { requestId });
      return;
    }

    payloadMessages.push({
      role: 'assistant',
      content: result.content || null,
      tool_calls: result.toolCalls
    });

    for (const toolCall of result.toolCalls) {
      const preview = previewForTool(toolCall);
      sender.send('assistant:activity', { requestId, event: `Requested ${preview.title}` });
      if (preview.requiresConfirmation && settings.confirmAgentActions) {
        const allowed = await confirmTool(preview);
        if (!allowed) {
          sender.send('assistant:activity', { requestId, event: `Skipped ${preview.title}` });
          payloadMessages.push({ role: 'tool', tool_call_id: toolCall.id, content: 'The user declined this local action.' });
          continue;
        }
      }

      sender.send('assistant:activity', { requestId, event: `Running ${preview.title}` });
      const output = await executeTool(toolCall);
      payloadMessages.push({ role: 'tool', tool_call_id: toolCall.id, content: output.slice(0, 24000) });
    }
  }

  sender.send('assistant:chunk', { requestId, content: 'Agent stopped after reaching the local tool limit. Ask me to continue if you want another pass.', reasoning: '' });
  sender.send('assistant:done', { requestId });
}

async function completeChatWithTools(apiKey, model, messages) {
  const response = await chatCompletion({ apiKey, model, messages, stream: false, tools: toolDefinitions });
  const json = await response.json();
  if (json.error?.message) {
    throw new Error(json.error.message);
  }

  const message = json.choices?.[0]?.message || {};
  return {
    content: message.content || '',
    reasoning: reasoningText(message),
    toolCalls: message.tool_calls || []
  };
}

function previewForTool(toolCall) {
  const name = toolCall.function?.name || 'local action';
  const args = parseToolArguments(toolCall);
  const writeTools = new Set(['write_text_file', 'create_directory', 'move_item', 'copy_item', 'trash_item', 'run_shell_command', 'open_item']);
  return {
    title: name.replace(/_/g, ' '),
    detail: JSON.stringify(args, null, 2),
    requiresConfirmation: writeTools.has(name)
  };
}

async function confirmTool(preview) {
  const result = await dialog.showMessageBox(assistantWindow, {
    type: preview.requiresConfirmation ? 'warning' : 'question',
    buttons: ['Allow', 'Cancel'],
    defaultId: 0,
    cancelId: 1,
    message: `Allow ${preview.title}?`,
    detail: preview.detail
  });
  return result.response === 0;
}

function parseToolArguments(toolCall) {
  try {
    return JSON.parse(toolCall.function?.arguments || '{}');
  } catch {
    throw new Error(`Invalid tool arguments for ${toolCall.function?.name || 'unknown tool'}.`);
  }
}

function expandPath(input) {
  const raw = String(input || '').trim();
  if (raw === '~') {
    return os.homedir();
  }
  if (raw.startsWith('~/')) {
    return path.join(os.homedir(), raw.slice(2));
  }
  return path.resolve(raw);
}

function assertSafeShellCommand(command) {
  const normalized = command.toLowerCase().replace(/\s+/g, ' ');
  const blocked = [
    /rm\s+-[^\n]*r[^\n]*f\s+\/($|\s)/,
    /mkfs\./,
    /diskutil\s+erase/,
    /format\s+[a-z]:/,
    /del\s+\/[fqs].*c:\\/,
    /dd\s+.*of=\/dev\//
  ];
  if (blocked.some((pattern) => pattern.test(normalized))) {
    throw new Error('CommandNest refused to run a shell command that appears to target the system destructively.');
  }
}

async function executeTool(toolCall) {
  try {
    const args = parseToolArguments(toolCall);
    switch (toolCall.function.name) {
      case 'list_directory':
        return fs.readdirSync(expandPath(args.path), { withFileTypes: true })
          .sort((a, b) => a.name.localeCompare(b.name))
          .map((entry) => `${entry.name}${entry.isDirectory() ? '/' : ''}`)
          .join('\n') || 'Directory is empty.';
      case 'read_text_file':
        return fs.readFileSync(expandPath(args.path), 'utf8').slice(0, Number(args.max_bytes || 120000));
      case 'write_text_file': {
        const target = expandPath(args.path);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, String(args.content || ''), 'utf8');
        return `Wrote ${Buffer.byteLength(String(args.content || ''))} bytes to ${target}.`;
      }
      case 'create_directory': {
        const target = expandPath(args.path);
        fs.mkdirSync(target, { recursive: true });
        return `Created directory ${target}.`;
      }
      case 'move_item': {
        const source = expandPath(args.source_path);
        const destination = expandPath(args.destination_path);
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.renameSync(source, destination);
        return `Moved ${source} to ${destination}.`;
      }
      case 'copy_item': {
        const source = expandPath(args.source_path);
        const destination = expandPath(args.destination_path);
        fs.mkdirSync(path.dirname(destination), { recursive: true });
        fs.cpSync(source, destination, { recursive: true, force: true });
        return `Copied ${source} to ${destination}.`;
      }
      case 'trash_item': {
        const target = expandPath(args.path);
        await shell.trashItem(target);
        return `Moved ${target} to Trash.`;
      }
      case 'open_item': {
        const target = String(args.path || '');
        if (target.startsWith('http://') || target.startsWith('https://')) {
          await shell.openExternal(target);
        } else {
          await shell.openPath(expandPath(target));
        }
        return `Opened ${target}.`;
      }
      case 'run_shell_command':
        assertSafeShellCommand(String(args.command || ''));
        return await runShellCommand(String(args.command || ''));
      default:
        throw new Error(`Unknown local agent tool: ${toolCall.function.name}`);
    }
  } catch (error) {
    return `Tool error: ${error.message}`;
  }
}

function runShellCommand(command) {
  return new Promise((resolve) => {
    const child = spawn(command, {
      shell: true,
      cwd: os.homedir(),
      timeout: 60000,
      windowsHide: true
    });
    let output = '';
    child.stdout.on('data', (data) => { output += data.toString(); });
    child.stderr.on('data', (data) => { output += data.toString(); });
    child.on('close', (code) => resolve(`${output}\nExit code: ${code}`.trim()));
    child.on('error', (error) => resolve(`Command failed: ${error.message}`));
  });
}

ipcMain.handle('settings:get', () => settingsForRenderer());
ipcMain.handle('settings:save', (_, payload) => {
  const apiKey = payload.apiKey === '********' ? loadAPIKey() : payload.apiKey;
  saveAPIKey(apiKey);
  const settings = saveSettings(payload);
  createMenu();
  return settingsForRenderer(settings);
});
ipcMain.handle('models:refresh', async () => fetchModels());
ipcMain.handle('window:close', () => assistantWindow?.hide());
ipcMain.handle('clipboard:copy', (_, text) => clipboard.writeText(String(text || '')));

ipcMain.handle('assistant:send', async (event, payload) => {
  const apiKey = loadAPIKey();
  if (!apiKey) {
    throw new Error('Add your OpenRouter API key in Settings before sending a prompt.');
  }

  const settings = loadSettings();
  const messages = payload.messages || [];
  const prompt = messages.at(-1)?.content || '';
  if (settings.agentModeEnabled && shouldUseLocalAgent(prompt)) {
    await runAgent(event.sender, payload.requestId, apiKey, payload.model || settings.selectedModelID, messages, settings);
  } else {
    await streamChat(event.sender, payload.requestId, apiKey, payload.model || settings.selectedModelID, messages);
  }

  return { ok: true };
});

app.whenReady().then(() => {
  app.setAppUserModelId(APP_ID);
  createWindow();
  createMenu();
  registerShortcut(loadSettings().shortcut);
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

app.on('window-all-closed', () => {});
