from base import *
body = cap("Compact · a finished cloud agent's PR went red") + compact('<span class="pill">🤖</span>', '<span class="pill">🎵</span>',
  peek='<span><b>Checks failed</b>&nbsp;<span class="s">· Devin: fix onboarding copy</span></span><span class="pill" style="height:18px;font-size:11px;padding:0 9px">Open PR</span>')
body += '<div class="note">setChecks(_, for:) already flips the row to checks.failed; the new bit is firing the existing finish-peek path once when a cloud thread lands on .failed. The strip names the agent and its PR; clicking opens the pull request. Honors Agents settings like other peeks.</div>'
open("m41.html","w").write(page("Agents: a peek when a cloud agent's checks fail","Users who merge agent PRs and would otherwise only notice red CI when they open Agents.",body))
