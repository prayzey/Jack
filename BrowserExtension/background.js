// Jack Tab Volume service worker. Connects to the WebSocket server Jack runs
// on loopback (BrowserTabBridge.swift), reports the tabs that make sound, and
// applies the volume and mute changes Jack sends back.

const JACK_URL = 'ws://127.0.0.1:51723/jack-tabs'; // BrowserTabBridge.port
const RECONNECT_ALARM = 'jack-reconnect';
const MAX_RETRY_MS = 30000;

// tabId -> gain (0...1), only for tabs not at full volume. Mirrored to
// storage.session because Chrome stops this worker when idle and every
// variable here is lost.
const gains = new Map();
const ready = chrome.storage.session
  .get('gains')
  .then(({ gains: saved }) => {
    for (const [id, gain] of Object.entries(saved ?? {})) gains.set(Number(id), gain);
  })
  .catch(() => {});

let socket = null;
let retryDelay = 1000;
let retryTimer = null;
let pingTimer = null;
let tabsTimer = null;
let lastTabs = '';

const gainOf = (tabId) => gains.get(tabId) ?? 1;

function saveGains() {
  chrome.storage.session.set({ gains: Object.fromEntries(gains) }).catch(() => {});
}

function browserName() {
  // Chromium adds a decoy "Not A;Brand" entry to discourage UA sniffing.
  // Prefer the product (Aside, Brave, Microsoft Edge) over the engine.
  const names = (navigator.userAgentData?.brands ?? [])
    .map(({ brand }) => brand)
    .filter((brand) => !/not.?a.?brand/i.test(brand));
  return names.find((brand) => brand !== 'Chromium') ?? names[0] ?? 'Browser';
}

function send(message) {
  if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
}

function connect() {
  if (socket) return; // open, or still connecting
  clearTimeout(retryTimer);
  const ws = new WebSocket(JACK_URL);
  socket = ws;
  ws.onopen = () => {
    retryDelay = 1000;
    lastTabs = '';
    send({ type: 'hello', version: 1, browser: browserName() });
    sendTabs();
    // Chrome stops an idle worker after 30 s, which would close the socket.
    // WebSocket traffic counts as activity (Chrome 116+).
    pingTimer = setInterval(() => send({ type: 'ping' }), 20000);
  };
  ws.onmessage = (event) => handleCommand(event.data);
  ws.onclose = () => {
    if (socket !== ws) return;
    socket = null;
    clearInterval(pingTimer);
    // Jack isn't running or just quit. The alarm below covers the case where
    // Chrome stops this worker and the timer never fires.
    retryTimer = setTimeout(connect, retryDelay);
    retryDelay = Math.min(retryDelay * 2, MAX_RETRY_MS);
  };
}

async function handleCommand(data) {
  let message;
  try {
    message = JSON.parse(data);
  } catch {
    return;
  }
  await ready;
  const { tabId } = message;
  switch (message.type) {
    case 'setVolume': {
      const volume = Number(message.volume);
      if (Number.isInteger(tabId) && Number.isFinite(volume)) setGain(tabId, Math.min(1, Math.max(0, volume)));
      break;
    }
    case 'setMuted':
      if (Number.isInteger(tabId)) chrome.tabs.update(tabId, { muted: Boolean(message.muted) }).catch(() => {});
      break;
    case 'requestTabs':
      lastTabs = '';
      sendTabs();
      break;
  }
}

function setGain(tabId, gain) {
  if (gain === 1) gains.delete(tabId);
  else gains.set(tabId, gain);
  saveGains();
  // No frameId, so every frame's content script in the tab gets it.
  chrome.tabs.sendMessage(tabId, { type: 'jack-gain', gain }).catch(() => {});
  scheduleTabs();
}

function scheduleTabs() {
  clearTimeout(tabsTimer);
  tabsTimer = setTimeout(sendTabs, 150);
}

async function sendTabs() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  await ready;
  // A tab the user turned down stays listed after it goes quiet, so it can
  // be turned back up.
  const tabs = (await chrome.tabs.query({}))
    .filter((tab) => tab.id >= 0 && (tab.audible || tab.mutedInfo?.muted || gainOf(tab.id) !== 1))
    .map((tab) => ({
      id: tab.id,
      title: tab.title ?? '',
      url: tab.url || tab.pendingUrl || null,
      favIconUrl: tab.favIconUrl || null,
      audible: Boolean(tab.audible),
      muted: Boolean(tab.mutedInfo?.muted),
      volume: gainOf(tab.id),
    }));
  const json = JSON.stringify({ type: 'tabs', tabs });
  if (json === lastTabs || socket?.readyState !== WebSocket.OPEN) return;
  lastTabs = json;
  socket.send(json);
}

chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  if ('audible' in change || 'mutedInfo' in change || tab.audible || tab.mutedInfo?.muted || gains.has(tabId)) {
    scheduleTabs();
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  ready.then(() => {
    if (gains.delete(tabId)) saveGains();
    scheduleTabs();
  });
});

// Chrome swaps in a new tab ID when a prerendered page takes over a tab, so
// carry the gain across.
chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
  ready.then(() => {
    const gain = gains.get(removedTabId);
    gains.delete(removedTabId);
    if (gain === undefined) scheduleTabs();
    else setGain(addedTabId, gain);
  });
});

// bridge.js asks on every page load, so new frames and navigations pick up
// the tab's current gain.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'jack-get-gain' || !sender.tab) return;
  ready.then(() => sendResponse({ gain: gainOf(sender.tab.id) }));
  return true; // reply asynchronously
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === RECONNECT_ALARM) connect();
});
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);

// Alarms survive the worker stopping, so this wakes it to retry while Jack
// isn't running. 30 s is the shortest period Chrome allows.
chrome.alarms.get(RECONNECT_ALARM).then((alarm) => {
  if (!alarm) chrome.alarms.create(RECONNECT_ALARM, { periodInMinutes: 0.5 });
});
connect();
