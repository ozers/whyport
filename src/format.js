import path from "node:path";

function meaningfulArgs(command) {
  const parts = (command ?? "").match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) ?? [];
  const kept = [];
  for (let index = 0; index < parts.length; index += 1) {
    const part = parts[index];
    if (part === "-cp" || part === "-classpath" || part === "--class-path") {
      index += 1;
      continue;
    }
    if (part.startsWith("-")) continue;
    kept.push(part.replace(/^['"]|['"]$/g, ""));
  }
  return kept;
}

export function guessRole(processName, command, cwd = "") {
  const args = meaningfulArgs(command);
  const tail = args.slice(-4).join(" ");
  const proc = `${processName ?? ""} ${path.basename(args[0] ?? "")}`.toLowerCase();
  const directory = cwd ?? "";

  if (/agentlib:jdwp|-xrunjdwp/i.test(command ?? "")) return "JDWP debugger";

  const gradle = tail.match(/GradleDaemon(?:\s+([0-9][\w.-]*))?/);
  if (gradle || directory.includes(`${path.sep}.gradle${path.sep}daemon${path.sep}`)) {
    return gradle?.[1] ? `Gradle daemon ${gradle[1]}` : "Gradle daemon";
  }

  if (/KotlinCompileDaemon/.test(tail) || directory.includes(`${path.sep}kotlin${path.sep}daemon`)) {
    const version = (command ?? "").match(/kotlin-daemon-embeddable-([0-9]+(?:\.[0-9]+)*)/)?.[1];
    return version ? `Kotlin daemon ${version}` : "Kotlin daemon";
  }

  if (proc.includes("docker")) return "Docker";
  if (/\bpostgres/.test(proc)) return "PostgreSQL";
  if (/redis-server/.test(proc)) return "Redis";
  if (/\bmysqld\b|mariadbd/.test(proc)) return "MySQL";
  if (/\bmongod\b/.test(proc)) return "MongoDB";
  if (/next-server|\bnext dev\b|\bnext start\b|\.bin\/next\b/.test(tail)) return "Next.js";
  if (/\bvite\b/.test(tail)) return "Vite";
  if (/webpack/.test(tail)) return "webpack";
  if (/uvicorn/.test(tail)) return "Uvicorn";
  if (/gunicorn/.test(tail)) return "Gunicorn";

  const script = args.find((part) => /\.(py|mjs|cjs|js|ts|rb|php)$/.test(part));
  if (script) return `${processName || "process"} · ${path.basename(script)}`;
  return processName || "process";
}

export function formatUptime(etime) {
  if (!etime) return "";
  const clock = etime.match(/^(?:(\d+)-)?(\d+):(\d+):(\d+)$/);
  if (clock) {
    const days = Number(clock[1] || 0);
    const hours = Number(clock[2]);
    const minutes = Number(clock[3]);
    if (days) return `${days}d ${hours}h`;
    if (hours) return `${hours}h ${minutes}m`;
    return `${minutes}m`;
  }
  const short = etime.match(/^(\d+):(\d+)$/);
  if (!short) return etime;
  const minutes = Number(short[1]);
  return minutes ? `${minutes}m` : `${Number(short[2])}s`;
}

export function shortWhy(row) {
  const parts = [];
  if (row.role) parts.push(row.role);
  if (row.project) parts.push(row.project);
  if (row.branch) parts.push(row.branch);
  if (row.bind === "localhost") parts.push("localhost only");
  else if (row.bind === "all") parts.push("all interfaces");
  return parts.join(" · ");
}

export function explainWhy(row, clients) {
  const role = row.role || row.process || "A process";
  const place = row.project
    ? `${row.project}${row.branch ? ` on ${row.branch}` : ""}${row.cwd ? ` (${row.cwd})` : ""}`
    : row.cwd || "an unknown directory";
  const bind =
    row.bind === "localhost"
      ? "only on localhost"
      : row.bind === "all"
        ? "on all interfaces"
        : `on ${row.bind}`;
  const sentences = [`${role} is listening ${bind} from ${place}.`];
  if (row.parent && row.ppid > 1) sentences.push(`Started by ${row.parent}.`);
  if (row.ppid === 1) {
    sentences.push(process.platform === "darwin" ? "Parent is launchd." : "Parent is pid 1.");
  }
  if (clients?.length === 0) sentences.push("Nothing is connected right now.");
  else if (clients?.length) {
    const peers = clients
      .map((client) => (client.process ? `${client.peer} (${client.process})` : client.peer))
      .join(", ");
    sentences.push(`In use by ${clients.length} connection${clients.length === 1 ? "" : "s"}: ${peers}.`);
  }
  return sentences.join(" ");
}

export function decorate(row, clients) {
  const role = guessRole(row.process, row.command, row.cwd);
  const next = { ...row, role };
  return { ...next, summary: shortWhy(next), why: explainWhy(next, clients) };
}

function fit(value, width) {
  const text = String(value ?? "");
  if (text.length <= width) return text.padEnd(width);
  if (width <= 1) return "…";
  return `${text.slice(0, width - 1)}…`;
}

export function formatTable(rows, columns = process.stdout.columns || 120) {
  if (rows.length === 0) return "No listening TCP ports.\n";
  const header = ["PORT", "BIND", "PID", "UP", "PROCESS", "PROJECT", "WHY"];
  const body = rows.map((row) => [
    String(row.port),
    row.bind,
    String(row.pid),
    formatUptime(row.uptime),
    row.process,
    row.project || "",
    row.summary || "",
  ]);
  const widthOf = (index) => Math.max(header[index].length, ...body.map((line) => line[index].length));
  const fixed = [0, 1, 2, 3, 4].map(widthOf);
  const projectWidth = Math.min(widthOf(5), 28);
  const gaps = 2 * (header.length - 1);
  const whyWidth = Math.max(24, columns - fixed.reduce((sum, width) => sum + width, 0) - projectWidth - gaps);
  const widths = [...fixed, projectWidth, whyWidth];
  const paint = (cols) => cols.map((col, index) => fit(col, widths[index])).join("  ").trimEnd();
  return [paint(header), ...body.map(paint)].join("\n") + "\n";
}

export function formatDetail(report) {
  if (report.listeners.length === 0) {
    return `Nothing is listening on ${report.port}.\n`;
  }
  return report.listeners
    .map((row) => {
      const lines = [
        `${row.port}  ${row.hosts.map((host) => `${host}:${row.port}`).join(", ")}`,
        `process   ${row.process} (${row.pid})`,
        `user      ${row.user || ""}`,
        `uptime    ${formatUptime(row.uptime)}`,
        `command   ${row.command || ""}`,
        `cwd       ${row.cwd || ""}`,
        `project   ${row.project || ""}`,
        `branch    ${row.branch || ""}`,
        `parent    ${row.parent || (row.ppid ? String(row.ppid) : "")}`,
        `why       ${row.why}`,
      ];
      if (report.clients.length === 0) lines.push("clients   none");
      else {
        lines.push("clients");
        for (const client of report.clients) {
          const who = client.process ? `${client.process} ${client.pid ?? ""}`.trim() : "peer";
          lines.push(`  ${client.peer}  ${who}`);
        }
      }
      return lines.join("\n");
    })
    .join("\n\n") + "\n";
}
