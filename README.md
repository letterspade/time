# Letterspade Time

Time tracking for Letterspade client work. A phone-first web app that installs to the home screen, with a shared database so the whole team's hours live in one place.

Live site: https://time.letterspade.com

## How it is built

- `index.html` — the whole app (timer, day calendar with drag-to-log, reports, team admin). No build step.
- `config.js` — the Supabase project URL and public anon key. Fill this in once.
- `supabase/schema.sql` — tables, access rules, and realtime. Run once in the Supabase SQL editor.
- `manifest.webmanifest`, `sw.js`, icons — what makes it installable and quick to open.
- `CNAME` — tells GitHub Pages to serve it at time.letterspade.com.

## One-time setup

1. **Supabase.** Create a free project at supabase.com. In the SQL editor, paste and run `supabase/schema.sql`. In Settings → API copy the Project URL and the `anon` `public` key into `config.js`. Under Authentication → URL Configuration, set the Site URL to `https://time.letterspade.com`.
2. **GitHub Pages.** Push this folder to a repository under the `letterspade` account and turn on Pages for the `main` branch. The `CNAME` file sets the custom domain.
3. **DNS.** At Squarespace Domains, add a CNAME record: host `time`, points to `letterspade.github.io`. Then in the repository's Pages settings tick "Enforce HTTPS" once the certificate appears.

## Accounts

- The first person to sign up becomes the admin automatically.
- Everyone after that signs up, then waits until an admin flips their switch in Account → Team.
- Admins see everyone's time, can edit it, and set each person's hourly pay for the By person report.
- Members see only their own time. Clients and projects are shared by the whole team.

## Everyday changes

Edit `index.html`, commit, push. GitHub Pages redeploys in about a minute. Bump `CACHE` in `sw.js` when you want phones to drop their cached copy immediately.
