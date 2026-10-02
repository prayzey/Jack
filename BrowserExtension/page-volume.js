// Page-world half of the volume hook. Scales everything the page plays by the
// tab's gain without the site noticing: media elements still report the
// volume the site set, and every AudioContext's output passes through a
// hidden gain node. Runs before any page script (document_start).
(() => {
  const FLAG = Symbol.for('jack-tab-volume');
  if (window[FLAG]) return;
  Object.defineProperty(window, FLAG, { value: true });

  let gain = 1;
  const media = HTMLMediaElement.prototype;
  const nativeVolume = Object.getOwnPropertyDescriptor(media, 'volume');
  const nativePlay = media.play;
  const NativeGainNode = window.GainNode;

  const intended = new WeakMap(); // element -> volume the site set
  // Elements feeding Web Audio. Their sound already passes through the hidden
  // gain node, so scaling the element too would apply the gain twice.
  const routed = new WeakSet();
  const tracked = new WeakSet();
  // WeakRefs, so tracking never keeps a finished `new Audio()` alive.
  const elements = new Set();
  const gainNodes = new Set();

  const applyGain = (element) =>
    nativeVolume.set.call(element, intended.get(element) * (routed.has(element) ? 1 : gain));

  function track(element) {
    if (tracked.has(element)) return;
    tracked.add(element);
    elements.add(new WeakRef(element));
    if (!intended.has(element)) {
      intended.set(element, nativeVolume.get.call(element));
      if (gain !== 1) applyGain(element);
    }
  }

  Object.defineProperty(media, 'volume', {
    configurable: true,
    enumerable: nativeVolume.enumerable,
    get() {
      return intended.has(this) ? intended.get(this) : nativeVolume.get.call(this);
    },
    set(value) {
      // Validate like the native setter, then set the scaled value once.
      // Setting the unscaled value first would fire volumechange on every
      // write, and sites that re-set volume from that event would loop.
      const volume = +value;
      if (!Number.isFinite(volume)) {
        throw new TypeError("Failed to set the 'volume' property on 'HTMLMediaElement': The provided double value is non-finite.");
      }
      if (volume < 0 || volume > 1) {
        throw new DOMException(
          `Failed to set the 'volume' property on 'HTMLMediaElement': The volume provided (${volume}) is outside the range [0, 1].`,
          'IndexSizeError',
        );
      }
      nativeVolume.set.call(this, volume * (routed.has(this) ? 1 : gain));
      intended.set(this, volume);
      track(this);
    },
  });

  // Catches elements that never join the DOM, like `new Audio(url).play()`.
  media.play = function play() {
    if (this instanceof HTMLMediaElement) track(this);
    return nativePlay.apply(this, arguments);
  };
  // Catches autoplay, which starts without a play() call. Media events don't
  // bubble, but a capturing listener still sees them.
  window.addEventListener('play', (event) => {
    if (event.target instanceof HTMLMediaElement) track(event.target);
  }, true);

  function findDescriptor(proto, name) {
    for (; proto; proto = Object.getPrototypeOf(proto)) {
      const descriptor = Object.getOwnPropertyDescriptor(proto, name);
      if (descriptor) return descriptor;
    }
  }

  // Patching AudioContext (not BaseAudioContext) leaves OfflineAudioContext
  // alone, so rendering a file offline isn't affected.
  for (const Context of new Set([window.AudioContext, window.webkitAudioContext])) {
    if (!Context || !NativeGainNode) continue;
    const proto = Context.prototype;
    const nativeDestination = findDescriptor(proto, 'destination');
    const nativeCreateSource = proto.createMediaElementSource;
    const hiddenNodes = new WeakMap(); // context -> its gain node

    Object.defineProperty(proto, 'destination', {
      configurable: true,
      enumerable: nativeDestination.enumerable,
      get() {
        let node = hiddenNodes.get(this);
        if (!node) {
          const real = nativeDestination.get.call(this);
          node = new NativeGainNode(this, { gain });
          node.connect(real);
          // Players size their output from these (Tone.js reads
          // maxChannelCount), so answer from the real destination.
          Object.defineProperty(node, 'maxChannelCount', { get: () => real.maxChannelCount });
          for (const name of ['channelCount', 'channelCountMode', 'channelInterpretation']) {
            Object.defineProperty(node, name, {
              get: () => real[name],
              set: (value) => {
                real[name] = value;
              },
            });
          }
          hiddenNodes.set(this, node);
          gainNodes.add(new WeakRef(node));
        }
        return node;
      },
    });

    if (nativeCreateSource) {
      proto.createMediaElementSource = function createMediaElementSource(element) {
        const source = nativeCreateSource.call(this, element);
        routed.add(element);
        track(element);
        applyGain(element);
        return source;
      };
    }
  }

  function setGain(value) {
    const next = Number(value);
    if (!Number.isFinite(next)) return;
    gain = Math.min(1, Math.max(0, next));
    for (const ref of elements) {
      const element = ref.deref();
      if (element) applyGain(element);
      else elements.delete(ref);
    }
    for (const ref of gainNodes) {
      const node = ref.deref();
      // A short ramp instead of a jump, so dragging the slider doesn't click.
      if (node) node.gain.setTargetAtTime(gain, node.context.currentTime, 0.015);
      else gainNodes.delete(ref);
    }
  }

  // Sent by bridge.js, which can talk to the extension.
  document.addEventListener('jack-tab-volume:gain', (event) => setGain(event.detail));
})();
