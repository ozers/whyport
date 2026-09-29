#!/usr/bin/env node
import { setTimeout as sleep } from "node:timers/promises";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { decorate, formatDetail, formatTable } from "./format.js";
import { inspectPort, listPorts, otherPorts } from "./scan.js";

const version = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8"),
).version;

const help = `whyport ${version}
See why a port is open, where it is used, and close it.

Usage
  whyport                     Live list, or print once when piped
  whyport list [--json]       Print listening TCP ports once
  whyport watch               Keep the list on screen
  whyport <port> [--json]     Why this port is open, and who is connected
  whyport kill <port>         Stop the listener with SIGTERM
  whyport kill <port> --force Stop it with SIGKILL
  whyport kill <port> --dry-run

Options
  --interval <seconds>        Refresh period for the live list (default 2)
  --json                      Machine-readable output
  --help                      Show this help
  --version                   Show the version

Reads lsof and ps on this machine. Nothing leaves the computer.
`;

function parseArgs(argv) {
  const options = { json: false, force: false, dryRun: false, interval: 2, positionals: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--json") options.json = true;
    else if (arg === "--force") options.force = true;
    else if (arg === "--dry-run") options.dryRun = true;
    else if (arg === "--help" || arg === "-h") options.help = true;
    else if (arg === "--version" || arg === "-v") options.version = true;
    else if (arg === "--interval") {
      options.interval = Number(argv[i + 1]);
      i += 1;
    } else if (arg.startsWith("-")) {
      throw new Error(`Unknown option ${arg}`);
    } else options.positionals.push(arg);
  }
  if (!Number.isFinite(options.interval) || options.interval <= 0) {
    throw new Error("--interval needs a positive number of seconds");
  }
  return options;
}

function parsePort(value) {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`Not a port: ${value}`);
  }
  return port;
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

async function rows() {
  return (await listPorts()).map((row) => decorate(row));
}

async function printList(json) {
  const list = await rows();
  if (json) printJson(list);
  else process.stdout.write(formatTable(list));
}

async function printPort(port, json) {
  const report = await inspectPort(port);
  const listeners = report.listeners.map((row) => decorate(row, report.clients));
  if (json) printJson({ port, listeners, clients: report.clients });
  else process.stdout.write(formatDetail({ port, listeners, clients: report.clients }));
  if (listeners.length === 0) process.exitCode = 1;
}

async function watch(interval) {
  const tty = process.stdout.isTTY;
  if (tty) process.stdout.write("\x1b[?25l");
  const abort = new AbortController();
  const finish = () => abort.abort();
  process.once("SIGINT", finish);
  process.once("SIGTERM", finish);
  try {
    while (!abort.signal.aborted) {
      const list = await rows();
      const body = formatTable(list);
      if (tty) process.stdout.write(`\x1b[2J\x1b[H${body}\nctrl-c to quit · every ${interval}s\n`);
      else process.stdout.write(body);
      await sleep(interval * 1000, null, { signal: abort.signal });
    }
  } catch (error) {
    if (error?.name !== "AbortError") throw error;
  } finally {
    if (tty) process.stdout.write("\x1b[?25h");
  }
}

async function killPort(port, { force, dryRun }) {
  const list = await listPorts();
  const targets = list.filter((row) => row.port === port);
  if (targets.length === 0) {
    process.stderr.write(`Nothing is listening on ${port}.\n`);
    process.exitCode = 1;
    return;
  }
  const signal = force ? "SIGKILL" : "SIGTERM";
  for (const target of targets) {
    const extra = otherPorts(list, target.pid, port);
    const also = extra.length ? ` (also closes ${extra.join(", ")})` : "";
    if (dryRun) {
      process.stdout.write(`would send ${signal} to ${target.pid} ${target.process} on ${port}${also}\n`);
      continue;
    }
    try {
      process.kill(target.pid, signal);
    } catch (error) {
      process.stderr.write(`could not signal ${target.pid} ${target.process}: ${error.code || error.message}\n`);
      process.exitCode = 1;
      continue;
    }
    await sleep(300);
    let gone = false;
    try {
      process.kill(target.pid, 0);
    } catch {
      gone = true;
    }
    const state = gone ? "stopped" : "still running";
    process.stdout.write(`${signal} ${target.pid} ${target.process} on ${port}${also} · ${state}\n`);
  }
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help) {
    process.stdout.write(help);
    return;
  }
  if (options.version) {
    process.stdout.write(`${version}\n`);
    return;
  }

  const [command, arg] = options.positionals;
  if (!command) {
    if (process.stdout.isTTY && !options.json) await watch(options.interval);
    else await printList(options.json);
    return;
  }
  if (command === "list") return printList(options.json);
  if (command === "watch") return watch(options.interval);
  if (command === "kill") return killPort(parsePort(arg), options);
  if (command === "why") return printPort(parsePort(arg), options.json);
  if (/^\d+$/.test(command)) return printPort(parsePort(command), options.json);
  throw new Error(`Unknown command ${command}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 2;
  });
}
