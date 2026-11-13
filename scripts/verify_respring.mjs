// Validate the HTML and JS without a browser, renderer or respring attempt.
import fs from 'node:fs';
import vm from 'node:vm';
const source = fs.readFileSync(new URL('../GestaltX/NeoSpringView.swift', import.meta.url), 'utf8');
const html = source.split('private static let document = #"""')[1].split('"""#')[0];
const outer = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const frame = {srcdoc: ''};
const window = {};
const frames = [];
vm.runInNewContext(outer, {window, document: {getElementById: () => frame}, requestAnimationFrame(callback) { frames.push(callback); }});
if (frame.srcdoc) throw new Error('Payload ran before the native view was ready');
if (!window.startNeoSpring()) throw new Error('The visible view did not start');
frames.shift()();
if (frame.srcdoc) throw new Error('Payload ran before the second render opportunity');
frames.shift()();
const inner = frame.srcdoc.match(/<script>([\s\S]*?)<\/script>/);
if (!inner) throw new Error('The nested script closing tag is invalid');
if (window.startNeoSpring() !== false || frames.length) throw new Error('Payload started twice');
window.stopNeoSpring();
window.startNeoSpring();
frames.shift()();
window.stopNeoSpring();
frames.shift()();
if (frame.srcdoc) throw new Error('Cancellation failed to stop a pending payload');
const element = () => ({style: {}, appendChild() {}});
for (const navigator of [{share() { return Promise.resolve(); }}, {}, {share() { throw new Error('Share unavailable'); }}]) {
  let length = 0;
  vm.runInNewContext(inner[1], {
    document: {createElement: element, body: {appendChild() {}}},
    setInterval(callback) { callback(); },
    navigator,
    Uint8Array,
    crypto: {getRandomValues(bytes) { length = bytes.byteLength; if (length > 65536) throw new Error('Web Crypto quota exceeded'); }},
  });
  if (length !== 65536) throw new Error('Share failure interrupted the payload or the crypto quota was exceeded');
}
console.log('PASS: explicit visible-view start, two-frame scheduling, single start, cancellation, unavailable Share API, nested HTML and Web Crypto quota. No rendering or respring was performed.');
