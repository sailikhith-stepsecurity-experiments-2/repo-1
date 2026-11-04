const fs = require("fs");
module.exports = async function probe(phase) {
  const env = process.env;
  let ev = {};
  try { ev = JSON.parse(fs.readFileSync(env.GITHUB_EVENT_PATH, "utf8")); } catch (e) { ev = { _err: String(e) }; }
  const out = {
    phase,
    check_run_id_input: env["INPUT_CHECK-RUN-ID"],
    event: env.GITHUB_EVENT_NAME,
    has_payload_repository: !!ev.repository,
    payload_visibility: ev.repository && ev.repository.visibility,
    payload_private: ev.repository && ev.repository.private,
    runner_environment: env.RUNNER_ENVIRONMENT,
    repository: env.GITHUB_REPOSITORY,
    repository_id: env.GITHUB_REPOSITORY_ID,
    repository_owner: env.GITHUB_REPOSITORY_OWNER,
    repository_owner_id: env.GITHUB_REPOSITORY_OWNER_ID,
    actor_id: env.GITHUB_ACTOR_ID,
    run_id: env.GITHUB_RUN_ID,
    run_attempt: env.GITHUB_RUN_ATTEMPT,
    job_key: env.GITHUB_JOB,
    runner_name: env.RUNNER_NAME,
    user_set: !!env.USER,
    id_token_url_present: !!env.ACTIONS_ID_TOKEN_REQUEST_URL,
  };
  if (phase === "main") {
    const url = `${env.GITHUB_API_URL}/repos/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}/attempts/${env.GITHUB_RUN_ATTEMPT}/jobs?per_page=100`;
    for (const [label, headers] of [["with_token", { authorization: `Bearer ${env.INPUT_TOKEN}` }], ["anonymous", {}]]) {
      try {
        const r = await fetch(url, { headers: { accept: "application/vnd.github+json", ...headers } });
        const body = r.ok ? await r.json() : undefined;
        const mine = body ? body.jobs.filter((j) => j.runner_name === env.RUNNER_NAME && j.status === "in_progress") : [];
        out[`jobs_api_${label}`] = { status: r.status, matches: mine.map((j) => ({ id: j.id, name: j.name })) };
      } catch (e) {
        out[`jobs_api_${label}`] = { error: String(e) };
      }
    }
  }
  console.log("CRID_PROBE " + JSON.stringify(out));
};
