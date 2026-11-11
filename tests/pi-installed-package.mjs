// Locate the package behind the active Pi command for installed-consumer tests.
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

try {
  const command = realpathSync(process.argv[2]);
  const install = join(dirname(dirname(command)), "install");
  const current = join(install, "current-version");
  let executable = command;
  if (existsSync(current)) {
    const version = readFileSync(current, "utf8").trim();
    if (!version || version === "." || version === ".." || !/^[\w.+-]+$/.test(version)) {
      throw new Error(`invalid managed Pi version in ${current}`);
    }
    executable = join(install, "releases", version, "node_modules", ".bin", "pi");
  }

  let dir = dirname(realpathSync(executable));
  for (let depth = 0; depth < 6; depth++, dir = dirname(dir)) {
    const manifest = join(dir, "package.json");
    if (existsSync(manifest) && JSON.parse(readFileSync(manifest, "utf8")).name === "@earendil-works/pi-coding-agent") {
      process.stdout.write(resolve(dir));
      process.exit(0);
    }
  }
  throw new Error(`Pi command does not belong to @earendil-works/pi-coding-agent: ${executable}`);
} catch (error) {
  console.error(`cannot locate installed Pi package: ${error.message}`);
  process.exit(1);
}
