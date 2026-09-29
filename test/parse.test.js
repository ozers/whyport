import assert from "node:assert/strict";
import test from "node:test";
import {
  classifyBind,
  groupClients,
  groupListeners,
  parseAddr,
  parseCwds,
  parseLsof,
  parsePs,
} from "../src/parse.js";

const LISTEN = `p4632
cjava
Lozersubasi
f349
n127.0.0.1:58501
TST=LISTEN
f485
n127.0.0.1:58512
TST=LISTEN
p23965
cfull-line-inference
Lozersubasi
f9
n[::1]:61412
TST=LISTEN
f10
n127.0.0.1:61412
TST=LISTEN
p6950
cjava
Lozersubasi
f284
n*:8083
TST=LISTEN
`;

test("parseAddr reads ipv4, ipv6, and wildcards", () => {
  assert.deepEqual(parseAddr("127.0.0.1:58501"), { host: "127.0.0.1", port: 58501 });
  assert.deepEqual(parseAddr("[::1]:61412"), { host: "::1", port: 61412 });
  assert.deepEqual(parseAddr("*:8083"), { host: "*", port: 8083 });
  assert.equal(parseAddr("127.0.0.1:3000->127.0.0.1:55123"), null);
});

test("groupListeners merges localhost v4 and v6 for one process", () => {
  const rows = groupListeners(parseLsof(LISTEN));
  assert.deepEqual(
    rows.map((row) => [row.port, row.pid, row.hosts]),
    [
      [8083, 6950, ["*"]],
      [58501, 4632, ["127.0.0.1"]],
      [58512, 4632, ["127.0.0.1"]],
      [61412, 23965, ["::1", "127.0.0.1"]],
    ],
  );
  assert.equal(classifyBind(["127.0.0.1", "::1"]), "localhost");
  assert.equal(classifyBind(["*"]), "all");
  assert.equal(classifyBind(["10.0.0.4"]), "10.0.0.4");
});

test("parsePs and parseCwds keep pid details", () => {
  const processes = parsePs(" 7142     1 03-18:46:58 /usr/bin/python mock.py\n");
  assert.equal(processes.get(7142).ppid, 1);
  assert.equal(processes.get(7142).etime, "03-18:46:58");
  assert.equal(processes.get(7142).command, "/usr/bin/python mock.py");

  const cwds = parseCwds("p7142\nfcwd\nn/tmp/local-dev\n");
  assert.equal(cwds.get(7142), "/tmp/local-dev");
});

test("groupClients prefers the peer process over the listener socket", () => {
  const text = `p7142
cpython
Luser
f4
n127.0.0.1:8090->127.0.0.1:55123
TST=ESTABLISHED
p900
cnode
Luser
f8
n127.0.0.1:55123->127.0.0.1:8090
TST=ESTABLISHED
`;
  const clients = groupClients(parseLsof(text), 8090, new Set([7142]));
  assert.deepEqual(clients, [{ peer: "127.0.0.1:55123", pid: 900, process: "node" }]);
});
