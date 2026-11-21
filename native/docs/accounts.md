# Agent Lab accounts

The same setup as Mavis final launch (its `App/Sources/Account.swift`, `ClaudeAccount.swift`, `Welcome.swift` and
`tools/accounts.sql` are the source of truth), in Agent Lab's own project with its own keys.

Two sign-ins, both asked by the welcome the first time Agent Lab opens:

1. **Agent Lab account** — Google sign-in through Agent Lab's Supabase project. Agent Lab only opens for an account
   that's been let in (`approved`); `waitlist` and `blocked` stay at the sign-in page. Checked at launch and every six
   hours; an approved check-in still counts offline for 14 days.
2. **Claude** — the Claude Code on this Mac, signed in with your Claude plan. Agents run on that plan only: API keys in
   the environment are removed before Claude Code starts (`engine/engine.js` `subscriptionEnvironment`).

## Turning accounts on

1. Create a Supabase project. In **SQL editor**, run `supabase/accounts.sql`, then `supabase/feedback.sql`.
2. In Google Cloud Console, create an OAuth client of type **Desktop app**. Copy its client ID and secret (for a
   desktop app the secret isn't secret; PKCE is the proof).
3. In Supabase: **Authentication → Sign In / Providers → Google**: turn it on and add that client ID under
   *Client IDs*.
4. Copy `accounts.env.example` to `accounts.env` and fill in the project URL, its publishable key, and the Google
   client ID and secret. `accounts.env` is ignored by git.
5. `./build.sh`. The build prints `accounts: on`.

Who gets in: `settings.signup_mode` is `open` (anyone who signs in) or `allowlist` (only emails in `allowlist`;
everyone else waits). Change a person's `profiles.status` in the Table Editor.

Without `accounts.env` the build has no accounts: the welcome skips signing in and only checks Claude.

    AgentLabNative --welcome     shows the whole welcome again
