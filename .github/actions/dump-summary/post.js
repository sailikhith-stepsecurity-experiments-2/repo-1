const fs = require("fs");
const path = require("path");
const dir = path.dirname(process.env.GITHUB_STEP_SUMMARY || "");
let files = [];
try {
  files = fs.readdirSync(dir).filter((f) => f.startsWith("step_summary_"));
} catch (e) {
  console.log(`cannot list ${dir}: ${e.message}`);
}
console.log(`${files.length} step summary file(s) in ${dir}`);
for (const f of files) {
  const body = fs.readFileSync(path.join(dir, f), "utf8");
  if (body.trim()) {
    console.log(`----- ${f}`);
    console.log(body);
    console.log(`----- end ${f}`);
  }
}
