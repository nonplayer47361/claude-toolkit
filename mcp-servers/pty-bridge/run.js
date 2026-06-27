#!/usr/bin/env node
/**
 * pty-bridge/run.js
 * ConPTY 래퍼: agy/codex를 headless 환경에서 실행하고 출력을 파일로 저장
 *
 * Usage:
 *   node run.js <cli> <output_file> [timeout_ms] -- <cli_args...>
 *
 * Examples:
 *   node run.js agy /tmp/out.txt 60000 -- --print "hello" --print-timeout 60s
 *   node run.js codex /tmp/out.txt 120000 -- exec -q "task text"
 */
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import fs from 'fs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const pty = require(join(__dirname, 'node_modules', 'node-pty'));

const [, , cli, outputFile, timeoutMsStr, ...rest] = process.argv;
const timeoutMs = parseInt(timeoutMsStr || '60000', 10);
// -- 구분자 이후를 args로
const sepIdx = rest.indexOf('--');
const cliArgs = sepIdx >= 0 ? rest.slice(sepIdx + 1) : rest;

if (!cli || !outputFile) {
  process.stderr.write('Usage: node run.js <cli> <output_file> [timeout_ms] -- <cli_args...>\n');
  process.exit(1);
}

// CLI 실행 파일 경로 해결
function resolveCli(name) {
  const which = process.env.PATH.split(';').map(p => join(p, name + '.exe')).find(p => {
    try { fs.accessSync(p); return true; } catch { return false; }
  });
  return which || name;
}

const exePath = resolveCli(cli);

const ptyProcess = pty.spawn(exePath, cliArgs, {
  name: 'xterm-color',
  cols: 220,
  rows: 50,
  cwd: process.cwd(),
  env: process.env,
});

let rawOutput = '';
ptyProcess.onData((data) => {
  rawOutput += data;
});

function finish(exitCode) {
  // OSC, CSI, DCS 이스케이프 시퀀스 제거
  const clean = rawOutput
    .replace(/\x1B\][^\x07\x1B]*(\x07|\x1B\\)/g, '') // OSC sequences
    .replace(/\x1B\[[0-9;?]*[A-Za-z]/g, '')           // CSI sequences
    .replace(/\x1B[()=><MNOPQRSTUVWXYZ\\^_`~]/g, '')  // 2-char escapes
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .trimEnd();

  fs.writeFileSync(outputFile, clean + '\n', 'utf8');
  process.stdout.write(clean + '\n');
  process.exit(exitCode ?? 0);
}

let finished = false;
ptyProcess.onExit(({ exitCode }) => {
  if (finished) return;
  finished = true;
  finish(exitCode);
});

setTimeout(() => {
  if (finished) return;
  finished = true;
  process.stderr.write(`[pty-bridge] timeout after ${timeoutMs}ms\n`);
  ptyProcess.kill();
  finish(1);
}, timeoutMs);
