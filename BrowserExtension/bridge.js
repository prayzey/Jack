// Isolated-world half of the volume hook. Content scripts in the page's own
// world (page-volume.js) can't use chrome.runtime, so this script carries the
// tab's gain from the service worker to it as a DOM event.

const relayGain = (gain) => document.dispatchEvent(new CustomEvent('jack-tab-volume:gain', { detail: gain }));

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === 'jack-gain') relayGain(message.gain);
});

// Every new document starts at full volume, so ask what this tab is set to.
chrome.runtime
  .sendMessage({ type: 'jack-get-gain' })
  .then((reply) => {
    if (typeof reply?.gain === 'number' && reply.gain !== 1) relayGain(reply.gain);
  })
  .catch(() => {}); // the extension was reloaded; this page keeps full volume
