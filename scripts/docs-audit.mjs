import assert from "node:assert/strict";
import {existsSync, readFileSync, readdirSync, statSync} from "node:fs";
import {dirname, relative, resolve, join} from "node:path";
import {fileURLToPath} from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const problems = [];
const documents = [];
const walk = directory => {
    for (const entry of readdirSync(directory, {withFileTypes: true})) {
        if (entry.name === ".git" || entry.name === "node_modules") continue;
        const path = join(directory, entry.name);
        if (entry.isDirectory()) walk(path);
        else if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) documents.push(path);
    }
};
walk(root);
const markdown = new Map(documents.map(path => [path, readFileSync(path, "utf8")]));
const headings = new Map();
const uniqueSlug = (title, seen) => {
    const base = title.toLowerCase()
        .replace(/`/g, "")
        .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
        .replace(/<[^>]*>/g, "")
        .replace(/[^\p{L}\p{N}_\- ]/gu, "")
        .trim()
        .replace(/ /g, "-");
    const previous = seen.get(base) || 0;
    seen.set(base, previous + 1);
    return previous === 0 ? base : `${base}-${previous}`;
};
for (const [path, content] of markdown) {
    let inFence = false;
    let marker = "";
    let titleCount = 0;
    const slugs = new Set();
    const seen = new Map();
    for (const [index, line] of content.split("\n").entries()) {
        const fence = /^\s{0,3}(`{3,}|~{3,})/.exec(line);
        if (fence) {
            const next = fence[1][0];
            if (!inFence) {inFence = true; marker = next;}
            else if (next === marker) inFence = false;
            continue;
        }
        if (inFence) continue;
        const heading = /^(#{1,6}) +(.+?)\s*#*\s*$/.exec(line);
        if (heading) {
            if (heading[1].length === 1) titleCount++;
            slugs.add(uniqueSlug(heading[2], seen));
        }
    }
    if (inFence) problems.push(`${relative(root, path)}: unclosed code fence`);
    if (titleCount !== 1) problems.push(`${relative(root, path)}: expected one H1, found ${titleCount}`);
    headings.set(path, slugs);
}
for (const [path, content] of markdown) {
    // Check local Markdown hyperlinks, including fragment links. Remote URLs are
    // deliberately excluded, because this is an offline source audit.
    for (const match of content.matchAll(/\]\(([^)]+)\)/g)) {
        const value = match[1].trim().split(/\s+"/)[0].replace(/^<|>$/g, "");
        if (!value || /^(https?:|mailto:|data:)/i.test(value)) continue;
        const [file, fragment] = value.split("#", 2);
        const target = file ? resolve(dirname(path), decodeURIComponent(file)) : path;
        if (!target.startsWith(root + "/") && target !== root) {
            problems.push(`${relative(root, path)}: link escapes repository: ${value}`);
            continue;
        }
        if (!existsSync(target)) {
            problems.push(`${relative(root, path)}: missing target ${value}`);
            continue;
        }
        if (fragment && markdown.has(target) && !headings.get(target).has(decodeURIComponent(fragment))) {
            problems.push(`${relative(root, path)}: missing heading anchor ${value}`);
        }
    }
}
assert(documents.length >= 15, "Expected NetStreamV2 Markdown documentation inventory");
if (problems.length) {
    for (const problem of problems) process.stderr.write(`DOC ERROR: ${problem}\n`);
    process.exitCode = 1;
} else {
    process.stdout.write(`PASS documentation: ${documents.length} Markdown files, heading/structure and local links validated\n`);
}
