export function parseAddr(name) {
  if (!name || name.includes("->")) return null;
  if (name.startsWith("[")) {
    const match = name.match(/^\[([^\]]+)\]:(\d+)$/);
    if (!match) return null;
    return { host: match[1], port: Number(match[2]) };
  }
  const index = name.lastIndexOf(":");
  if (index <= 0) return null;
  const port = Number(name.slice(index + 1));
  if (!Number.isInteger(port)) return null;
  return { host: name.slice(0, index), port };
}

export function parseEndpoint(name) {
  if (!name?.includes("->")) return null;
  const [local, remote] = name.split("->");
  const localAddr = parseAddr(local);
  const remoteAddr = parseAddr(remote);
  if (!localAddr || !remoteAddr) return null;
  return { local, remote, localAddr, remoteAddr };
}

export function parseLsof(text) {
  const processes = [];
  let current = null;
  let file = null;

  for (const line of text.split("\n")) {
    if (!line) continue;
    const id = line[0];
    const value = line.slice(1);
    if (id === "p") {
      current = { pid: Number(value), command: "", user: "", files: [] };
      processes.push(current);
      file = null;
      continue;
    }
    if (!current) continue;
    if (id === "c") current.command = value;
    else if (id === "L") current.user = value;
    else if (id === "f") {
      file = { fd: value, name: "", state: "" };
      current.files.push(file);
    } else if (id === "n" && file) file.name = value;
    else if (id === "T" && file && value.startsWith("ST=")) file.state = value.slice(3);
  }

  return processes;
}

export function parsePs(text) {
  const processes = new Map();
  for (const line of text.split("\n")) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\S+)\s+(.*)$/);
    if (!match) continue;
    processes.set(Number(match[1]), {
      pid: Number(match[1]),
      ppid: Number(match[2]),
      etime: match[3],
      command: match[4].trim(),
    });
  }
  return processes;
}

export function parseCwds(text) {
  const cwds = new Map();
  for (const proc of parseLsof(text)) {
    const cwd = proc.files.find((file) => file.fd === "cwd" && file.name);
    if (cwd) cwds.set(proc.pid, cwd.name);
  }
  return cwds;
}

const LOOPBACK = new Set(["127.0.0.1", "::1", "localhost"]);
const WILDCARD = new Set(["*", "0.0.0.0", "::", "::0"]);

export function classifyBind(hosts) {
  if (!hosts?.length) return "unknown";
  if (hosts.every((host) => LOOPBACK.has(host))) return "localhost";
  if (hosts.some((host) => WILDCARD.has(host))) return "all";
  return [...new Set(hosts)].join(", ");
}

export function groupListeners(processes) {
  const groups = new Map();
  for (const proc of processes) {
    for (const file of proc.files) {
      if (file.state !== "LISTEN") continue;
      const addr = parseAddr(file.name);
      if (!addr) continue;
      const key = `${proc.pid}:${addr.port}`;
      let group = groups.get(key);
      if (!group) {
        group = {
          pid: proc.pid,
          port: addr.port,
          process: proc.command,
          user: proc.user,
          hosts: [],
        };
        groups.set(key, group);
      }
      if (!group.hosts.includes(addr.host)) group.hosts.push(addr.host);
    }
  }
  return [...groups.values()].sort((a, b) => a.port - b.port || a.pid - b.pid);
}

export function groupClients(processes, port, listenerPids) {
  const byPeer = new Map();
  for (const proc of processes) {
    for (const file of proc.files) {
      if (file.state && file.state !== "ESTABLISHED") continue;
      const endpoint = parseEndpoint(file.name);
      if (!endpoint) continue;
      const isClient = endpoint.remoteAddr.port === port && !listenerPids.has(proc.pid);
      const isServer = endpoint.localAddr.port === port;
      if (!isClient && !isServer) continue;
      const peer = isClient ? endpoint.local : endpoint.remote;
      const current = byPeer.get(peer);
      const next = {
        peer,
        pid: isClient ? proc.pid : null,
        process: isClient ? proc.command : null,
      };
      if (!current || (next.pid && !current.pid)) byPeer.set(peer, next);
    }
  }
  return [...byPeer.values()];
}
