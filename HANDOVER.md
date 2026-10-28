# Zeta Pharma: handover notes (28 Oct 2026)

## Repositories

| Repo | URL | Branch | Last commit | Holds |
|---|---|---|---|---|
| ph | https://github.com/AshrafRezk/ph | `main` | 588ae64, 22 Sep 2026 | Salesforce project + offline Field PWA (`offline/`, `offline-runtime/`), plans in `Plan/` |
| Zeta | https://github.com/Jennyazmy/Zeta | `main` | a89e620, 23 Sep 2026 (Omar Hazem) | Earlier Salesforce project copy (CLM work) |

Other branch: `origin/cursor/offline-tabs-list-modal` in `ph` (6 Sep 2026, already merged into main).

Ask Ashraf for collaborator access to both repos.

## Warning: git is about a month behind

The latest work is not in either repo yet.

- The newest Salesforce source is in the main project folder (`Zeta Pharma/force-app`). That folder is not a git repo. It has about 1,100 Apex classes, compared with about 530 in `ph`. About 1,150 of its files changed after 20 Oct.
- `ph` has about 350 modified and 530 untracked files that were never committed.
- `Jennyazmy-Zeta` has about 140 modified and 60 untracked files that were never committed.

Until this is committed and pushed, the repos alone are **not** enough to continue the work.

## Salesforce org

- Production org: **ZetaPharma** (alias `ZetaPharma`, Org Id `00Dhk000002KJ8dEAG`). There is no sandbox in use, so every deploy goes to production.
- Log in with `sf org login web --alias ZetaPharma` using credentials from Ashraf.

## Rules that are easy to miss

1. **Never push `ph` to `main` before the working copy is committed.** Netlify builds salesforceoffline.com from `main`, so pushing the stale code rolls the site back by weeks.
2. **Deploy the PWA by hand** from `ph/offline`:
   `npm run build`, then
   `netlify deploy --prod --no-build --dir=dist --functions=netlify/functions --site d46a554a-27f8-44ec-a39f-f36ae015202a`
3. **Production deploys:** first retrieve the org's current permission sets and flexipages, then add only your entry to them. Deploy new fields and their FLS before the code and tests that use them.
4. **Dry runs:** `sf project deploy start --dry-run` can print "Failing: 0" and still fail on coverage below 75%. Check the exit code and grep the output for "coverage". Include every test class that covers the class you deploy.
5. **Admin console testing in prod:** exports are real, but stop imports at the preview step.
6. **Historical imports:** leave/TOT rows for ex-employees need the user activated for a short window (`.tmp_28oct_fix/swap_active.py`). After visit loads, run `EmployeeTimeCardBackfillBatch` (batch size 1) for the loaded months.
7. **Class Engine:** managers set their subordinates' account visit frequency per month, not once per quarter. This change is still pending.
8. **Brick maps:** built by `scripts/bricks/build_admin_bricks.py` from CAPMAS/HDX boundaries. Do not go back to the old Google circles script.

## Secrets

`ph/offline/.env*` and the org credentials must not be committed or shared in chat. Pass them on privately.
