import assert from "node:assert/strict";
import test from "node:test";
import { decorate, explainWhy, formatUptime, guessRole, shortWhy } from "../src/format.js";

test("formatUptime collapses ps elapsed time", () => {
  assert.equal(formatUptime("03-18:46:58"), "3d 18h");
  assert.equal(formatUptime("02:14:00"), "2h 14m");
  assert.equal(formatUptime("18:05"), "18m");
  assert.equal(formatUptime("00:04"), "4s");
});

test("guessRole prefers the framework over the runtime", () => {
  assert.equal(guessRole("node", "node /app/node_modules/.bin/next dev"), "Next.js");
  assert.equal(guessRole("Python", "/usr/bin/Python /work/mock-services.py"), "Python · mock-services.py");
  assert.equal(guessRole("postgres", "postgres -D /data"), "PostgreSQL");
  assert.equal(
    guessRole("java", "java -cp /caches/org.postgresql/r2dbc-postgresql/1.jar com.example.App"),
    "java",
  );
  assert.equal(
    guessRole("java", "java -cp /gradle/lib.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 9.7.1"),
    "Gradle daemon 9.7.1",
  );
  assert.equal(
    guessRole("com.docker.backend", "/Applications/Docker.app/Contents/MacOS/com.docker.backend services"),
    "Docker",
  );
  assert.equal(
    guessRole(
      "java",
      "java kotlin-daemon-embeddable-2.3.21.jar org.jetbrains.kotlin.daemon.KotlinCompileDaemon",
    ),
    "Kotlin daemon 2.3.21",
  );
});

test("explainWhy names the project, the bind, and the clients", () => {
  const row = decorate({
    process: "node",
    command: "node /repo/node_modules/.bin/next dev",
    project: "web",
    branch: "main",
    cwd: "/repo/web",
    bind: "localhost",
    ppid: 40,
    parent: "npm",
  });
  assert.equal(row.role, "Next.js");
  assert.match(shortWhy(row), /Next\.js · web · main · localhost only/);
  const why = explainWhy(row, [{ peer: "127.0.0.1:55123", process: "chrome" }]);
  assert.match(why, /Next\.js is listening only on localhost from web on main/);
  assert.match(why, /Started by npm/);
  assert.match(why, /chrome/);
});
