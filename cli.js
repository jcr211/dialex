#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import process from 'node:process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function printUsage() {
  console.log(`Dialex

Usage:
  dialex install
  dialex uninstall

Commands:
  install    Copy Dialex into your Codex profile and install the audio bridge
  uninstall  Remove the Dialex profile hook and installed files
`);
}

function resolvePowerShell() {
  const candidates = process.platform === 'win32'
    ? ['pwsh.exe', 'powershell.exe']
    : ['pwsh', 'powershell'];

  for (const command of candidates) {
    const check = spawnSync(command, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'], { stdio: 'ignore' });
    if (!check.error && check.status === 0) {
      return command;
    }
  }

  return null;
}

function runScript(scriptName) {
  const ps = resolvePowerShell();
  if (!ps) {
    console.error('PowerShell was not found. Dialex is currently Windows/PowerShell only.');
    process.exit(1);
  }

  const script = path.join(__dirname, scriptName);
  const result = spawnSync(
    ps,
    ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script],
    { stdio: 'inherit' },
  );

  process.exit(result.status ?? 1);
}

const [command] = process.argv.slice(2);

if (!command || command === '-h' || command === '--help') {
  printUsage();
  process.exit(0);
}

if (command === 'install') {
  runScript('install.ps1');
} else if (command === 'uninstall') {
  runScript('uninstall.ps1');
} else {
  printUsage();
  process.exit(1);
}

