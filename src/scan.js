import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { classifyBind, groupClients, groupListeners, parseCwds, parseLsof, parsePs } from "./parse.js";
import { detectProject } from "./project.js";

const execFileAsync = promisify(execFile);

async function run(command, args) {
  try {
    const { stdout } = await execFileAsync(command, args, {
      timeout: 10000,
      maxBuffer: 10 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    if (error.code === "ENOENT") {
      throw new Error(`whyport needs ${command}, and it was not found on PATH.`);
    }
    return error.stdout ?? "";
  }
}

async function loadProjects(cwds) {
  const projects = new Map();
  for (const cwd of new Set(cwds.values())) {
    projects.set(cwd, await detectProject(cwd));
  }
  return projects;
}

export async function listPorts() {
  const listenText = await run("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLnT"]);
  const grouped = groupListeners(parseLsof(listenText));
  const pids = [...new Set(grouped.map((row) => row.pid))];
  if (pids.length === 0) return [];

  const [psText, cwdText] = await Promise.all([
    run("ps", ["-p", pids.join(","), "-o", "pid=,ppid=,etime=,command="]),
    run("lsof", ["-nP", "-a", "-p", pids.join(","), "-d", "cwd", "-F", "pn"]),
  ]);
  const processes = parsePs(psText);
  const cwds = parseCwds(cwdText);
  const projects = await loadProjects(cwds);

  return grouped.map((row) => {
    const proc = processes.get(row.pid);
    const cwd = cwds.get(row.pid) ?? null;
    const project = cwd ? projects.get(cwd) : null;
    return {
      port: row.port,
      pid: row.pid,
      process: proc ? commandName(proc.command) || row.process : row.process,
      user: row.user,
      command: proc?.command || row.process,
      ppid: proc?.ppid ?? null,
      uptime: proc?.etime || "",
      cwd,
      project: project?.name ?? null,
      projectRoot: project?.root ?? null,
      branch: project?.branch ?? null,
      hosts: row.hosts,
      bind: classifyBind(row.hosts),
    };
  });
}

function commandName(command) {
  const token = command?.split(/\s+/)[0];
  if (!token) return "";
  const base = token.split("/").pop();
  return base || token;
}

export async function inspectPort(port) {
  const rows = await listPorts();
  const listeners = rows.filter((row) => row.port === port);
  if (listeners.length === 0) return { port, listeners, clients: [] };

  const text = await run("lsof", ["-nP", `-iTCP:${port}`, "-sTCP:ESTABLISHED", "-F", "pcLnT"]);
  const clients = groupClients(
    parseLsof(text),
    port,
    new Set(listeners.map((row) => row.pid)),
  );
  const parents = new Map();
  await Promise.all(
    [...new Set(listeners.map((row) => row.ppid).filter((ppid) => ppid > 1))].map(async (ppid) => {
      const psText = await run("ps", ["-p", String(ppid), "-o", "comm="]);
      const name = psText.trim().split("/").pop();
      if (name) parents.set(ppid, name);
    }),
  );

  return {
    port,
    listeners: listeners.map((row) => ({
      ...row,
      parent: row.ppid === 1 ? (process.platform === "darwin" ? "launchd" : "pid 1") : parents.get(row.ppid) ?? null,
    })),
    clients,
  };
}

export function otherPorts(rows, pid, port) {
  return rows.filter((row) => row.pid === pid && row.port !== port).map((row) => row.port);
}
