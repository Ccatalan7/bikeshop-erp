import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const files = execFileSync("git", ["ls-files", "-z", "*.md"], {
  cwd: root,
  encoding: "utf8",
})
  .split("\0")
  .filter(Boolean)
  .filter(
    (file) =>
      !file.includes("/") ||
      /^(?:docs\/(?:architecture|development|guides|runbooks)\/)/u.test(file),
  );
const failures = [];

for (const file of files) {
  const markdown = readFileSync(resolve(root, file), "utf8").replace(
    /```[\s\S]*?```/g,
    "",
  );
  const links = /!?\[[^\]]*\]\(([^)\n]+)\)/g;
  for (const match of markdown.matchAll(links)) {
    let target = match[1].trim();
    if (target.startsWith("<")) {
      target = target.slice(1, target.indexOf(">"));
    } else {
      target = target.split(/\s+["']/u, 1)[0];
    }
    if (/^(?:https?:|file:|mailto:|tel:|#)/iu.test(target)) continue;
    target = target.split("#", 1)[0];
    if (!target) continue;

    try {
      target = decodeURIComponent(target);
    } catch {
      failures.push(`${file}: malformed link target ${target}`);
      continue;
    }

    const relativeAbsolute = target.startsWith("/")
      ? resolve(root, `.${target}`)
      : resolve(root, dirname(file), target);
    const repositoryAbsolute = resolve(root, target.replace(/^\.\//u, ""));
    if (!existsSync(relativeAbsolute) && !existsSync(repositoryAbsolute)) {
      failures.push(`${file}: missing ${target}`);
    }
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log(`Local Markdown links passed (${files.length} files).`);
