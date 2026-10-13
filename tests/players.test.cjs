const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

function harness(file, search) {
  const elements = {};
  const messages = [], timers = [], players = [], requests = [];
  function element(id) {
    return elements[id] ||= {style: {}, classList: {add() {}, remove() {}},
      addEventListener() {}, removeEventListener() {}, pause() {this.paused = true;},
      removeAttribute() {this.currentSrc = '';}, load() {}, canPlayType() {return '';},
      play() {return Promise.resolve();}, paused: false, currentTime: 0};
  }
  const context = {URL, URLSearchParams, console, Date, Promise,
    location: {search, origin: 'https://mmuz86.github.io'},
    document: {getElementById: element, hidden: false, addEventListener() {},
      createElement() {return {};}, body: {appendChild() {}}, head: {appendChild() {}}},
    setTimeout(fn, ms) {timers.push({fn, ms}); return timers.length;}, clearTimeout() {},
    setInterval(fn) {context.tick = fn;},
    fetch() {return new Promise(resolve => requests.push(resolve));}};
  class Hls {
    static isSupported() {return true;}
    static Events = {MANIFEST_PARSED:'manifest', ERROR:'error'};
    static ErrorTypes = {NETWORK_ERROR:'network', MEDIA_ERROR:'media'};
    constructor() {this.events = {}; players.push(this);}
    on(event, fn) {this.events[event] = fn;}
    loadSource(url) {this.url = url;}
    attachMedia() {}
    destroy() {this.destroyed = true;}
    startLoad() {}
    recoverMediaError() {}
  }
  const ytPlayers = [];
  context.YT = {PlayerState: {PLAYING:1, BUFFERING:3, PAUSED:2, ENDED:0},
    Player: function (_, options) {
      this.options = options; this.time = 0; this.state = 1;
      this.destroy = () => {this.destroyed = true;};
      this.getCurrentTime = () => this.time;
      this.getPlayerState = () => this.state;
      ytPlayers.push(this);
    }};
  context.window = {...context, Hls, parent: {postMessage(payload, origin) {messages.push({payload, origin});}}};
  let source = fs.readFileSync(file, 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
  const exports = file.startsWith('hls') ? '{start,startWith,fail,markPlaying,tellApp,isHdUrl}' : '{build,showError,stalled}';
  source = source.replace(/\}\)\(\);\s*$/, `window.testing = ${exports};\n})();`);
  vm.runInNewContext(source, context);
  return {api: context.window.testing, context, elements, messages, timers, players, requests, ytPlayers};
}
const flush = async () => {for (let i = 0; i < 8; i++) await Promise.resolve();};

test('HLS status uses exact approved origins; HD rejects hostile URLs', () => {
  const h = harness('hls-player.html', '?c=quran');
  h.api.tellApp('playing');
  assert.deepEqual(h.messages.map(m => m.origin), ['https://getyaqeen.com','https://www.getyaqeen.com','https://app.getyaqeen.com']);
  for (const url of ['http://live.kwikmotion.com/a','https://live.kwikmotion.com.evil.test/a','https://user@live.kwikmotion.com/a']) assert.equal(h.api.isHdUrl(url), false);
});
test('SD failure after playing still performs the longer HD retry', async () => {
  const h = harness('hls-player.html', '?c=quran');
  h.requests[0]({ok:false}); await flush();
  h.api.markPlaying(); h.api.fail('sd_404');
  assert.ok(h.timers.some(t => t.ms === 12000));
  h.requests[1]({ok:true, json: async () => ({url:'https://api.getyaqeen.com/live/hls/quran/master.m3u8'})}); await flush();
  assert.match(h.players.at(-1).url, /master.m3u8$/);
  h.api.fail('hd_failed'); h.api.fail('sd_failed');
  assert.equal(h.requests.length, 2);
  assert.equal(JSON.parse(h.messages.at(-1).payload).kind, 'error');
});
test('obsolete HLS events and HD resolution cannot overwrite a user retry', async () => {
  const h = harness('hls-player.html', '?c=sunnah');
  h.requests[0]({ok:false}); await flush();
  const old = h.players.at(-1);
  h.api.fail('sd_404'); h.api.start();
  old.events.error(null, {fatal:true, type:'network'});
  h.requests[1]({ok:true, json:async () => ({url:'https://live.kwikmotion.com/old'})}); await flush();
  assert.equal(h.players.length, 1);
  h.requests[2]({ok:false}); await flush();
  assert.equal(h.players.length, 2);
});
test('YouTube freeze recovery is bounded and reserves nocookie for embed errors', () => {
  const h = harness('live-player.html', '?v=abcdefghijk');
  h.api.build();
  for (let i = 0; i < 4; i++) h.api.stalled();
  assert.equal(h.ytPlayers.length, 4);
  assert.ok(h.ytPlayers.every(p => p.options.host === 'https://www.youtube.com'));
  assert.ok(h.ytPlayers.every(p => p.destroyed));
  const old = h.ytPlayers[0]; old.options.events.onError({data:150});
  assert.equal(h.ytPlayers.length, 4);
  h.api.build(); h.ytPlayers.at(-1).options.events.onError({data:150});
  assert.equal(h.ytPlayers.at(-1).options.host, 'https://www.youtube-nocookie.com');
});
test('YouTube pause and hidden page do not trigger freeze recovery', () => {
  const h = harness('live-player.html', '?v=abcdefghijk'); h.api.build();
  const p = h.ytPlayers[0]; p.options.events.onStateChange({data:1});
  p.state = 2; for (let i = 0; i < 10; i++) h.context.tick();
  p.state = 1; h.context.document.hidden = true;
  for (let i = 0; i < 10; i++) h.context.tick();
  assert.equal(h.ytPlayers.length, 1);
});
test('error overlays have a layer above video and controls', () => {
  for (const file of ['hls-player.html','live-player.html']) assert.match(fs.readFileSync(file,'utf8'), /#m\{[^}]*z-index:10/);
});
