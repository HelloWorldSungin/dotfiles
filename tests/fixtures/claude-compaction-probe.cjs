// Read-only, version-specific native-function probe. No Claude process or API.
// Run: node tests/fixtures/claude-compaction-probe.cjs /path/to/claude/2.1.272
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const cp = require('node:child_process');
const os = require('node:os');
const path = require('node:path');
const source = fs.readFileSync(process.argv[2], 'utf8');
assert(source.includes('env:Kc().optional().describe("Environment variables to set for Claude Code sessions")'));
assert(source.includes('autoCompactWindow:ru().describe("Auto-compact window size")'));
assert(source.includes('YLe=1e5,I6e=1e6;'));
function extract(name) {
  const start = source.indexOf(`function ${name}(`);
  assert(start >= 0, `missing ${name}`);
  const next = source.indexOf('function ', start + 9);
  // Drop trailing module declarations; these functions have no nested functions.
  return source.slice(start, source.lastIndexOf('}', next) + 1);
}
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-window-'));
try {
  for (const override of [undefined, '400000']) {
    const file = path.join(temporary, 'settings.json');
    fs.writeFileSync(file, JSON.stringify({env: {OTHER: 'keep', ...(override ? {CLAUDE_CODE_AUTO_COMPACT_WINDOW: override} : {})}}));
    cp.execFileSync('bash', [path.resolve(__dirname, '../../bin/claude-set-compaction-window')], {
      env: {...process.env, CLAUDE_CONFIG_DIR: temporary}
    });
    const settings = JSON.parse(fs.readFileSync(file));
    assert.equal(settings.env.OTHER, 'keep');
    for (const modelWindow of [200000, 1000000]) {
      // Model/account dependencies are fixture inputs. Decimal parsing is stubbed;
      // native Dne validates/caps it, Gw resolves/clamps, t2 reserves output,
      // C1e and awt compute the actual installed thresholds.
      const ctx = {process: {env: settings.env}, yp: () => ({}), ze: x => x,
        pp: () => modelWindow, fGn: () => undefined, Tl: Number, t: () => {},
        YLe: 100000, I6e: 1000000, CWe: () => 20000, rXn: 20000, ff: () => true};
      vm.createContext(ctx);
      vm.runInContext(['Dne', 'Gw', 't2', 'C1e', 'awt'].map(extract).join('\n'), ctx);
      const window = Math.min(modelWindow, Number(override || 600000));
      assert.equal(ctx.Gw('fixture', 300000).window, window); // env wins settings
      assert.equal(ctx.Gw('fixture').source, 'env');
      assert.equal(ctx.C1e(ctx.t2('fixture'), {}), window - 33000);
      assert.equal(ctx.C1e(ctx.t2('fixture'), {testPctOverride: 50}), (window - 20000) / 2);
      assert.equal(ctx.awt(ctx.t2('fixture'), {precomputeBufferFraction: 0.2}), (window - 20000) * 0.8);
      ctx.CWe = () => 0;
      assert.equal(ctx.C1e(ctx.t2('fixture'), {}), window - 13000);
      console.log(JSON.stringify({override, modelWindow, effectiveWindow: window,
        reservedThreshold: window - 33000, zeroReserveThreshold: window - 13000}));
    }
  }
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
