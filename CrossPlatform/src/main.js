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
  const actionWords = ['create', 'make', 'write', 'edit', 'modify', 'change', 'organize', 'move', 'rename', 'delete', 'trash', 'copy', 'read', 'list', 'show', 'find', 'search', 'inspect', 'open', 'run', 'execute', 'install', 'build', 'test', 'fix', 'debug', 'send', 'email', 'mail', 'browse', 'browser', 'commit', 'push', 'pull request', 'release', 'github', 'mcp'];
  const targets = ['file', 'files', 'folder', 'folders', 'directory', 'directories', 'downloads', 'desktop', 'documents', 'project', 'app', 'code', 'terminal', 'command', 'script', 'repo', 'repository', '.js', '.ts', '.md', '.txt', '~/', '/users/', 'c:\\', 'github', 'browser', 'chrome', 'edge', 'firefox', 'website', 'web page', 'email', 'mail', 'mcp', 'server'];
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
  tool('run_shell_command', 'Run a shell command on the local machine.', { command: prop('Command to run'), working_directory: prop('Optional working directory'), timeout_seconds: prop('Optional timeout from 1 to 600 seconds', 'number') }, ['command']),
  tool('open_item', 'Open a file, folder, app, or URL.', { path: prop('Path or URL') }, ['path']),
  tool('search_files', 'Search for files or folders by name under a local root path.', { root_path: prop('Root path'), query: prop('Filename or path substring'), max_results: prop('Optional result limit', 'number') }, ['root_path', 'query']),
  tool('grep_text', 'Search text contents under a local root path using ripgrep when available.', { root_path: prop('Root path'), pattern: prop('Literal or regex pattern'), max_results: prop('Optional result limit', 'number') }, ['root_path', 'pattern']),
  tool('replace_in_text_file', 'Replace text in a local UTF-8 text file.', { path: prop('File path'), find: prop('Exact text to find'), replacement: prop('Replacement text'), replace_all: prop('Whether to replace all occurrences', 'boolean') }, ['path', 'find', 'replacement']),
  tool('run_project_tests', 'Run tests for a local project. Provide command for custom projects, or let CommandNest infer common runners.', { project_path: prop('Project root'), command: prop('Optional test command'), timeout_seconds: prop('Optional timeout from 1 to 600 seconds', 'number') }, ['project_path']),
  tool('git_status', 'Show git status for a local repository.', { repository_path: prop('Local git repository path') }, ['repository_path']),
  tool('git_diff', 'Show git diff and diff stat for a local repository.', { repository_path: prop('Local git repository path'), pathspec: prop('Optional pathspec'), max_bytes: prop('Optional output size limit', 'number') }, ['repository_path']),
  tool('git_commit', 'Stage selected paths or all changes and create a git commit.', { repository_path: prop('Local git repository path'), message: prop('Commit message'), paths: prop('Optional comma-separated path list') }, ['repository_path', 'message']),
  tool('git_push', 'Push a local git branch to a remote.', { repository_path: prop('Local git repository path'), remote: prop('Optional remote name'), branch: prop('Optional branch name') }, ['repository_path']),
  tool('github_create_pull_request', 'Create a GitHub pull request with the gh CLI.', { repository_path: prop('Local repository path'), title: prop('Pull request title'), body: prop('Pull request body'), base: prop('Optional base branch'), head: prop('Optional head branch'), draft: prop('Create a draft pull request', 'boolean') }, ['repository_path', 'title']),
  tool('github_create_release', 'Create a GitHub release with the gh CLI.', { repository_path: prop('Local repository path'), tag: prop('Release tag'), title: prop('Optional release title'), notes: prop('Optional release notes'), asset_paths: prop('Optional comma-separated asset paths') }, ['repository_path', 'tag']),
  tool('browser_navigate', 'Open a URL in the default browser.', { url: prop('Full URL to open') }, ['url']),
  tool('search_web', 'Open a web search in the default browser.', { query: prop('Search query') }, ['query']),
  tool('compose_email', 'Open an email draft in the default mail app.', { to: prop('Comma-separated recipients'), cc: prop('Optional CC'), bcc: prop('Optional BCC'), subject: prop('Subject'), body: prop('Body') }, ['to']),
  tool('send_email', 'Open a completed email draft for review. Automatic send requires a configured OS mail automation or MCP mail server.', { to: prop('Comma-separated recipients'), cc: prop('Optional CC'), bcc: prop('Optional BCC'), subject: prop('Subject'), body: prop('Body') }, ['to', 'subject', 'body']),
  tool('mcp_list_servers', 'List built-in and user-configured MCP stdio servers available to CommandNest.', {}, []),
  tool('mcp_list_tools', 'Connect to an MCP stdio server and list its tools.', { server_id: prop('MCP server id'), timeout_seconds: prop('Optional timeout', 'number') }, ['server_id']),
  tool('mcp_call_tool', 'Call a tool on a configured MCP stdio server. This always requires confirmation because external MCP tools can perform arbitrary actions.', { server_id: prop('MCP server id'), tool_name: prop('MCP tool name'), arguments: prop('Tool arguments as object or JSON string', 'object'), timeout_seconds: prop('Optional timeout', 'number') }, ['server_id', 'tool_name', 'arguments'])
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

Local Agent Mode is enabled. You are an acting desktop, coding, browser, email, GitHub, and MCP agent, not an advice bot. When the user asks you to create, edit, organize, inspect, move, rename, run, install, build, test, browse, send email, commit, push, create a pull request, create a release, call an MCP server, or otherwise change something on this computer, use tools to do it. Do not answer with generic instructions for tasks you can perform. Prefer the smallest effective action. Use absolute paths when possible. Read repository state before editing code, run relevant tests after changes, and summarize exact files or commands used. Sending email, browser control, GitHub uploads, shell commands, writes, and external MCP calls require user confirmation. After using tools, explain what you changed or found concisely.`;
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
  const writeTools = new Set([
    'write_text_file',
    'create_directory',
    'move_item',
    'copy_item',
    'trash_item',
    'run_shell_command',
    'open_item',
    'replace_in_text_file',
    'run_project_tests',
    'git_commit',
    'git_push',
    'github_create_pull_request',
    'github_create_release',
    'browser_navigate',
    'search_web',
    'compose_email',
    'send_email',
    'mcp_call_tool'
  ]);
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
      case 'search_files':
        return searchFiles(args);
      case 'grep_text':
        return await grepText(args);
      case 'replace_in_text_file':
        return replaceInTextFile(args);
      case 'run_project_tests':
        return await runProjectTests(args);
      case 'git_status':
        return await runShellCommand(`git -C ${shellQuote(expandPath(args.repository_path))} status --short --branch`, expandPath(args.repository_path), 30);
      case 'git_diff':
        return await gitDiff(args);
      case 'git_commit':
        return await gitCommit(args);
      case 'git_push':
        return await gitPush(args);
      case 'github_create_pull_request':
        return await githubCreatePullRequest(args);
      case 'github_create_release':
        return await githubCreateRelease(args);
      case 'browser_navigate':
        await shell.openExternal(String(args.url || ''));
        return `Opened ${args.url}.`;
      case 'search_web': {
        const url = new URL('https://www.google.com/search');
        url.searchParams.set('q', String(args.query || ''));
        await shell.openExternal(url.toString());
        return `Opened web search for ${args.query}.`;
      }
      case 'compose_email':
        await shell.openExternal(mailtoURL(args));
        return `Opened an email draft to ${splitList(args.to).join(', ')}.`;
      case 'send_email':
        await shell.openExternal(mailtoURL(args));
        return 'Opened a completed email draft for review. Automatic sending is available through a configured MCP mail server or platform-specific mail automation.';
      case 'mcp_list_servers':
        return mcpListServers();
      case 'mcp_list_tools':
        return await mcpListTools(args);
      case 'mcp_call_tool':
        return await mcpCallTool(args);
      case 'run_shell_command':
        assertSafeShellCommand(String(args.command || ''));
        return await runShellCommand(String(args.command || ''), args.working_directory ? expandPath(args.working_directory) : os.homedir(), Number(args.timeout_seconds || 60));
      default:
        throw new Error(`Unknown local agent tool: ${toolCall.function.name}`);
    }
  } catch (error) {
    return `Tool error: ${error.message}`;
  }
}

function splitList(value) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item || '').trim()).filter(Boolean);
  }
  return String(value || '')
    .split(/[,\n]/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function shellQuote(value) {
  if (process.platform === 'win32') {
    return `"${String(value).replace(/"/g, '\\"')}"`;
  }
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function searchFiles(args) {
  const root = expandPath(args.root_path);
  const query = String(args.query || '').toLowerCase();
  const maxResults = Math.min(Math.max(Number(args.max_results || 100), 1), 500);
  const skip = new Set(['.git', 'node_modules', 'dist', 'build', 'DerivedData', '.build']);
  const results = [];

  function walk(current) {
    if (results.length >= maxResults) {
      return;
    }
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (skip.has(entry.name)) {
        continue;
      }
      const fullPath = path.join(current, entry.name);
      if (entry.name.toLowerCase().includes(query) || fullPath.toLowerCase().includes(query)) {
        results.push(fullPath);
        if (results.length >= maxResults) {
          return;
        }
      }
      if (entry.isDirectory()) {
        walk(fullPath);
      }
    }
  }

  walk(root);
  return results.join('\n') || 'No matching files found.';
}

async function grepText(args) {
  const root = expandPath(args.root_path);
  const pattern = String(args.pattern || '');
  const maxResults = Math.min(Math.max(Number(args.max_results || 100), 1), 500);
  const command = process.platform === 'win32'
    ? `findstr /spin /c:${shellQuote(pattern)} *`
    : `if command -v rg >/dev/null 2>&1; then rg -n --hidden --glob '!.git/**' --glob '!node_modules/**' --glob '!dist/**' --glob '!build/**' ${shellQuote(pattern)} ${shellQuote(root)} | head -n ${maxResults}; else grep -RIn --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build ${shellQuote(pattern)} ${shellQuote(root)} | head -n ${maxResults}; fi`;
  return await runShellCommand(command, root, Number(args.timeout_seconds || 30));
}

function replaceInTextFile(args) {
  const target = expandPath(args.path);
  const find = String(args.find || '');
  const replacement = String(args.replacement || '');
  const original = fs.readFileSync(target, 'utf8');
  if (!original.includes(find)) {
    return `No matching text found in ${target}.`;
  }

  const updated = args.replace_all
    ? original.split(find).join(replacement)
    : original.replace(find, replacement);
  const count = args.replace_all ? original.split(find).length - 1 : 1;
  fs.writeFileSync(target, updated, 'utf8');
  return `Replaced ${count} occurrence${count === 1 ? '' : 's'} in ${target}.`;
}

function inferTestCommand(projectPath) {
  if (fs.existsSync(path.join(projectPath, 'package.json'))) {
    return 'npm test';
  }
  if (fs.existsSync(path.join(projectPath, 'pyproject.toml')) || fs.existsSync(path.join(projectPath, 'pytest.ini'))) {
    return process.platform === 'win32' ? 'python -m pytest' : 'python3 -m pytest';
  }
  if (fs.existsSync(path.join(projectPath, 'Package.swift'))) {
    return 'swift test';
  }
  throw new Error('No test command was provided and no known project test runner was detected.');
}

async function runProjectTests(args) {
  const projectPath = expandPath(args.project_path);
  const command = String(args.command || '').trim() || inferTestCommand(projectPath);
  return await runShellCommand(command, projectPath, Number(args.timeout_seconds || 120));
}

async function gitDiff(args) {
  const repo = expandPath(args.repository_path);
  const pathspec = String(args.pathspec || '').trim();
  const diffCommand = pathspec
    ? `git -C ${shellQuote(repo)} diff -- ${shellQuote(pathspec)}`
    : `git -C ${shellQuote(repo)} diff`;
  const output = await runShellCommand(`git -C ${shellQuote(repo)} diff --stat && ${diffCommand}`, repo, 60);
  return output.slice(0, Number(args.max_bytes || 80000));
}

async function gitCommit(args) {
  const repo = expandPath(args.repository_path);
  const paths = splitList(args.paths);
  const addCommand = paths.length
    ? `git -C ${shellQuote(repo)} add -- ${paths.map(shellQuote).join(' ')}`
    : `git -C ${shellQuote(repo)} add -A`;
  return await runShellCommand(`${addCommand} && git -C ${shellQuote(repo)} commit -m ${shellQuote(args.message || 'Update')}`, repo, 120);
}

async function gitPush(args) {
  const repo = expandPath(args.repository_path);
  const remote = String(args.remote || 'origin').trim();
  const branch = String(args.branch || '').trim();
  return await runShellCommand(`git -C ${shellQuote(repo)} push ${shellQuote(remote)}${branch ? ` ${shellQuote(branch)}` : ''}`, repo, 180);
}

async function githubCreatePullRequest(args) {
  const repo = expandPath(args.repository_path);
  let command = `gh pr create --title ${shellQuote(args.title || 'Update')} --body ${shellQuote(args.body || '')}`;
  if (args.base) command += ` --base ${shellQuote(args.base)}`;
  if (args.head) command += ` --head ${shellQuote(args.head)}`;
  if (args.draft !== false) command += ' --draft';
  return await runShellCommand(command, repo, 180);
}

async function githubCreateRelease(args) {
  const repo = expandPath(args.repository_path);
  let command = `gh release create ${shellQuote(args.tag)}`;
  const assets = splitList(args.asset_paths).map((asset) => shellQuote(expandPath(asset)));
  if (assets.length) command += ` ${assets.join(' ')}`;
  if (args.title) command += ` --title ${shellQuote(args.title)}`;
  if (args.notes) command += ` --notes ${shellQuote(args.notes)}`;
  return await runShellCommand(command, repo, 240);
}

function mailtoURL(args) {
  const url = new URL(`mailto:${splitList(args.to).join(',')}`);
  if (args.subject) url.searchParams.set('subject', String(args.subject));
  if (args.body) url.searchParams.set('body', String(args.body));
  if (args.cc) url.searchParams.set('cc', splitList(args.cc).join(','));
  if (args.bcc) url.searchParams.set('bcc', splitList(args.bcc).join(','));
  return url.toString();
}

function mcpServerConfigs() {
  const builtIns = {
    filesystem: {
      name: 'Filesystem MCP',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-filesystem', os.homedir()],
      env: {}
    },
    github: {
      name: 'GitHub MCP',
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-github'],
      env: {}
    },
    browser: {
      name: 'Playwright Browser MCP',
      command: 'npx',
      args: ['-y', '@playwright/mcp@latest'],
      env: {}
    }
  };
  for (const candidate of [
    path.join(os.homedir(), '.commandnest', 'mcp.json'),
    userDataPath('mcp.json')
  ]) {
    if (!fs.existsSync(candidate)) continue;
    try {
      const parsed = JSON.parse(fs.readFileSync(candidate, 'utf8'));
      for (const [id, config] of Object.entries(parsed.mcpServers || {})) {
        builtIns[id] = {
          name: config.name || id,
          command: config.command,
          args: config.args || [],
          env: config.env || {}
        };
      }
    } catch {
      // Ignore invalid optional MCP config so built-in presets keep working.
    }
  }
  return builtIns;
}

function mcpListServers() {
  return Object.entries(mcpServerConfigs())
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([id, config]) => `${id}: ${config.name}\n  command: ${config.command} ${(config.args || []).map(shellQuote).join(' ')}`)
    .join('\n\n');
}

async function mcpListTools(args) {
  const client = new MCPStdioClient(mcpServerConfig(args.server_id), Number(args.timeout_seconds || 45) * 1000);
  const result = await client.listTools();
  return result.map((item) => item.description ? `- ${item.name}: ${item.description}` : `- ${item.name}`).join('\n') || `MCP server ${args.server_id} returned no tools.`;
}

async function mcpCallTool(args) {
  const client = new MCPStdioClient(mcpServerConfig(args.server_id), Number(args.timeout_seconds || 90) * 1000);
  const toolArguments = typeof args.arguments === 'string' ? JSON.parse(args.arguments || '{}') : (args.arguments || {});
  return await client.callTool(String(args.tool_name || ''), toolArguments);
}

function mcpServerConfig(serverId) {
  const config = mcpServerConfigs()[serverId];
  if (!config) {
    throw new Error(`Unknown MCP server '${serverId}'. Call mcp_list_servers first.`);
  }
  return config;
}

function runShellCommand(command, cwd = os.homedir(), timeoutSeconds = 60) {
  return new Promise((resolve) => {
    const child = spawn(command, {
      shell: true,
      cwd,
      timeout: Math.min(Math.max(Number(timeoutSeconds || 60), 1), 600) * 1000,
      windowsHide: true
    });
    let output = '';
    child.stdout.on('data', (data) => { output += data.toString(); });
    child.stderr.on('data', (data) => { output += data.toString(); });
    child.on('close', (code) => resolve(`${output}\nExit code: ${code}`.trim()));
    child.on('error', (error) => resolve(`Command failed: ${error.message}`));
  });
}

class MCPStdioClient {
  constructor(config, timeoutMs) {
    this.config = config;
    this.timeoutMs = timeoutMs;
    this.nextId = 1;
    this.buffer = Buffer.alloc(0);
    this.pending = new Map();
    this.process = null;
  }

  async listTools() {
    return await this.withSession(async () => {
      const result = await this.request('tools/list', {});
      return (result.tools || []).map((item) => ({
        name: item.name,
        description: item.description || ''
      })).filter((item) => item.name);
    });
  }

  async callTool(name, args) {
    return await this.withSession(async () => {
      const result = await this.request('tools/call', { name, arguments: args });
      return this.renderToolResult(result);
    });
  }

  async withSession(callback) {
    await this.start();
    try {
      await this.initialize();
      return await callback();
    } finally {
      this.close();
    }
  }

  async start() {
    this.process = spawn(this.config.command, this.config.args || [], {
      env: { ...process.env, ...(this.config.env || {}) },
      shell: false,
      windowsHide: true
    });

    this.process.stdout.on('data', (chunk) => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      this.drainMessages();
    });
    this.process.stderr.on('data', () => {});
    this.process.on('exit', () => {
      for (const { reject } of this.pending.values()) {
        reject(new Error('MCP server exited before responding.'));
      }
      this.pending.clear();
    });
    this.process.on('error', (error) => {
      for (const { reject } of this.pending.values()) {
        reject(error);
      }
      this.pending.clear();
    });
  }

  async initialize() {
    await this.request('initialize', {
      protocolVersion: '2024-11-05',
      capabilities: {},
      clientInfo: {
        name: 'CommandNest',
        version: app.getVersion()
      }
    });
    this.send({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
  }

  request(method, params) {
    const id = this.nextId;
    this.nextId += 1;
    const promise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`MCP request timed out: ${method}`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
    });
    this.send({ jsonrpc: '2.0', id, method, params });
    return promise.then((message) => {
      if (message.error) {
        throw new Error(message.error.message || JSON.stringify(message.error));
      }
      return message.result || {};
    });
  }

  send(message) {
    const body = Buffer.from(JSON.stringify(message), 'utf8');
    this.process.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
    this.process.stdin.write(body);
  }

  drainMessages() {
    while (true) {
      const delimiter = this.buffer.indexOf('\r\n\r\n');
      if (delimiter === -1) return;
      const header = this.buffer.slice(0, delimiter).toString('utf8');
      const match = header.match(/content-length:\s*(\d+)/i);
      if (!match) {
        this.buffer = this.buffer.slice(delimiter + 4);
        continue;
      }
      const length = Number(match[1]);
      const bodyStart = delimiter + 4;
      const bodyEnd = bodyStart + length;
      if (this.buffer.length < bodyEnd) return;
      const body = this.buffer.slice(bodyStart, bodyEnd).toString('utf8');
      this.buffer = this.buffer.slice(bodyEnd);

      let message;
      try {
        message = JSON.parse(body);
      } catch {
        continue;
      }
      const pending = this.pending.get(message.id);
      if (!pending) continue;
      clearTimeout(pending.timer);
      this.pending.delete(message.id);
      pending.resolve(message);
    }
  }

  renderToolResult(result) {
    const prefix = result.isError ? 'MCP tool returned an error.\n' : '';
    if (!Array.isArray(result.content) || !result.content.length) {
      return prefix + JSON.stringify(result, null, 2);
    }
    return prefix + result.content.map((item) => item.text || item.uri || JSON.stringify(item, null, 2)).join('\n');
  }

  close() {
    if (!this.process) return;
    try {
      this.process.stdin.end();
    } catch {}
    if (!this.process.killed) {
      this.process.kill();
    }
  }
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
