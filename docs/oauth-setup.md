# Setting Up Google, Apple & Facebook Sign-In

All three providers are fully built underneath, but clicking a button
returns a `503 Service Unavailable` until real credentials are set on the
Container App. This doc walks through getting those credentials for each.

The "Continue with Google" and "Continue with Facebook" buttons appear on
`/signup`, `/account-login`, `/login`, and `/account.html` — both are
configured and live. Apple's button is still **hidden** site-wide (via a
`hidden` attribute in each page's HTML) since it isn't configured yet — once
you have real credentials, remove the `hidden` attribute from its
`.oauth-btn-apple` elements in `customer/signup.html`,
`customer/account-login.html`, and `staff/login.html` to bring it back.

Customers can use any provider to sign in self-serve. Staff can only *link*
an existing username/password account to Google/Apple/Facebook from
`/account.html` — they can't create a brand-new staff account through OAuth.

Once you have the values below, send them over (or set them yourself — see
[Applying the values](#applying-the-values)) and sign-in for that provider
goes live immediately, no redeploy needed.

## Google (free, ~10 minutes)

**Already configured, but needs a redirect URI update.** Google sign-in has
real credentials set since 2026-07-25, registered against the old Azure
hostname. Now that `PublicBaseURL.swift`'s fallback points at
`www.ohanasushigrill.com`, the app requests that URI instead — go add
`https://www.ohanasushigrill.com/auth/google/callback` to the **Authorized
redirect URIs** list in step 4 below (the Azure one can stay too, no need to
remove it) or Google sign-in will start failing with a redirect_uri_mismatch
error as soon as this deploys.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a new project, or pick an existing one, from the project dropdown at the top of the page.
2. In the left sidebar, go to **APIs & Services → OAuth consent screen**. If you haven't configured this before:
   - User type: **External**
   - Fill in the basic app info (app name, support email, developer contact email) — no Google verification review is needed for a small user base like this.
3. Go to **APIs & Services → Credentials** → **Create Credentials → OAuth client ID**.
   - Application type: **Web application**
   - Name it whatever you like (e.g. "Ohana Belltown Web")
4. Under **Authorized redirect URIs**, add exactly this one URL — both customer and staff sign-in share it, dispatched internally by the app:
   - `https://www.ohanasushigrill.com/auth/google/callback`
   - Optional, for testing locally: also add `http://localhost:8080/auth/google/callback`
5. Click **Create**. Google shows you a **Client ID** and **Client Secret** — copy both.

These become:
- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`

After a successful Google sign-in, both customers and staff land on
`/logged-in`, a small router page that checks the session and forwards
staff to `/edit.html` and customers to `/my-account.html`.

## Apple (has a real cost — $99/year Apple Developer Program)

1. Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) if you haven't already. This is a paid, once-a-year membership; there's no way around the cost for Sign in with Apple.
2. Once enrolled, go to [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list) (**Certificates, IDs & Profiles → Identifiers**):
   - If you don't already have an **App ID** for the site, register one, and make sure the **Sign in with Apple** capability is checked.
   - Then register a **Services ID** — this is a second, separate identifier (e.g. `com.ohanabelltown.web`). This Services ID string is your `APPLE_OAUTH_CLIENT_ID`.
   - Configure the Services ID's "Sign in with Apple" settings with:
     - Domain: `www.ohanasushigrill.com`
     - Return URLs:
       - `https://www.ohanasushigrill.com/auth/apple/customer/callback`
       - `https://www.ohanasushigrill.com/auth/apple/staff/callback`
3. Go to **Certificates, IDs & Profiles → Keys** and create a new key:
   - Check **Sign in with Apple**, and associate it with the Services ID from step 2.
   - Click **Continue**, then **Register**, then **Download**. Apple only lets you download this `.p8` file **once** — save it somewhere safe immediately.
   - Note the **Key ID** shown on the confirmation screen (a 10-character code).
4. Find your **Team ID** — it's shown in the top-right of the developer portal, or under **Membership** in the sidebar (also a 10-character code, different from the Key ID).

These become:
- `APPLE_OAUTH_CLIENT_ID` — the Services ID string (e.g. `com.ohanabelltown.web`)
- `APPLE_OAUTH_TEAM_ID` — the Team ID
- `APPLE_OAUTH_KEY_ID` — the Key ID
- `APPLE_OAUTH_PRIVATE_KEY` — the full contents of the downloaded `.p8` file, including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines

## Facebook (free, ~10 minutes)

**Already configured.** Real credentials set on the Container App since
2026-09-08. The app is currently in **Development Mode** — only accounts
added as testers/admins under **App Roles** in the Facebook developer
dashboard can actually complete sign-in; everyone else gets an error from
Facebook itself. Switch the app to **Live** (Basic Settings requires a
privacy policy URL — `https://www.ohanasushigrill.com/privacy` already works
for this) once real customers should be able to use it.

Steps followed, for reference (or if credentials ever need regenerating):

1. Go to [developers.facebook.com/apps](https://developers.facebook.com/apps/) and create a new app (choose the "Consumer" or "None" use case — no business verification is needed for basic Facebook Login).
2. From the app dashboard, add the **Facebook Login** product.
3. Under **Facebook Login → Settings**, add this to **Valid OAuth Redirect URIs** — both customer and staff sign-in share it, dispatched internally by the app, same as Google:
   - `https://www.ohanasushigrill.com/auth/facebook/callback`
   - Optional, for testing locally: also add `http://localhost:8080/auth/facebook/callback`
4. Under **App Settings → Basic**, copy the **App ID** and **App Secret**.
5. Still under **App Settings → Basic**, scroll to **Data Deletion Request** (required before the
   app can go Live) and set the **Data Deletion Request URL** to:
   - `https://www.ohanasushigrill.com/auth/facebook/data-deletion`
   - This is a real, working callback (`FacebookDataDeletion.swift` / `OAuthRoutes.swift`) — when a
     user asks Facebook to delete their data via Facebook's own settings, Facebook POSTs a signed
     request here, the app verifies it (HMAC-SHA256 with the App Secret) and deletes/unlinks any
     matching customer or staff account, then returns a confirmation URL
     (`/data-deletion-status`) for Facebook to show the user. No manual follow-up needed.
   - Separately, customers can also self-serve a full account deletion any time from
     `/my-account.html`, independent of Facebook — see `CustomerUserStore.deleteAccount`.

These became:
- `FACEBOOK_OAUTH_APP_ID`
- `FACEBOOK_OAUTH_APP_SECRET`

### Going Live — App Review / Data Handling questionnaire

Before Facebook lets the app leave Development Mode, its dashboard asks for
a description (sometimes phrased as a "data flow diagram") of how each
requested permission is used. Ready-to-paste answers, generated from what
`FacebookOAuth.swift`/`CustomerUsers.swift` actually do:

**`public_profile`** — "Ohana Belltown (www.ohanasushigrill.com) uses
public_profile solely to let guests and staff sign in and create an account
with one tap, instead of a separate username/password. We read the user's
Facebook id and name via `graph.facebook.com/me`: the id links their
Facebook login to their own account in our system so a returning user is
recognized, and the name pre-fills their display name, which they can edit
any time from their account page. We also fetch their public profile
picture (via the `/{user-id}/picture` edge) to show as their avatar. None
of this data is sold, shared with third parties, or used for advertising —
it's stored only in this application's own database to support login and
account display."

**`email`** — "Ohana Belltown uses the email permission to create the
account itself, since our sign-in system is email-based — we require an
email address to open a session and identify the account uniquely. The
email Facebook returns is stored as the account's email address, exactly
the same field a user gets from signing up with a plain email/password.
It's never shared with third parties or used for marketing without a
separate opt-in."

**`user_birthday`** (added 2026-09-26 — requires its own Advanced Access
request under **Permissions and Features**, separate from the
`public_profile`/`email` default access above) — "Ohana Belltown uses
user_birthday to offer the user's Birthday Club perk (one free bonus punch
on their sushi punch card every year on their birthday) without asking them
to type their birthday in twice. We discard the year entirely — only the
month and day are ever stored (`CustomerUser.birthday`, format `MM-DD`) —
and only fill this field the first time it's empty; a user's own edit from
their account page always takes precedence and is never overwritten by a
later Facebook login. The birthday is shown back to the user on their own
account page and can be changed or cleared there at any time, independent
of Facebook."

**Data deletion** — "If a user removes Ohana Belltown from their Facebook
account, or requests deletion via Facebook's own settings, Facebook sends a
signed server-to-server request to our Data Deletion Request URL
(`https://www.ohanasushigrill.com/auth/facebook/data-deletion`). We verify
the request's signature with our App Secret, then permanently delete the
matching customer account and all associated data (email, name, profile
photo reference, loyalty/rewards records) from our database. If the
Facebook-linked account belongs to restaurant staff rather than a customer,
we only remove the Facebook connection itself — the underlying employment
account isn't something Facebook created, so the staff member keeps normal
username/password login. We return a confirmation URL
(`https://www.ohanasushigrill.com/data-deletion-status`) that Facebook
shows the user. Customers can also delete their account directly, any
time, from `https://www.ohanasushigrill.com/my-account.html`, independent
of Facebook."

A diagram matching the same flow (guest → Facebook OAuth → Graph API →
this app's own `CustomerUser` record → what it's used for → the two
independent deletion paths) is at
[`docs/images/facebook-data-flow.png`](images/facebook-data-flow.png) —
upload it directly if the dashboard specifically asks for an image/diagram
rather than free text. If Facebook also asks for a screen recording of the
login flow, the real one on `/account-login` or `/signup` is enough — no
separate demo needed, since it's live and working end to end already.

## Applying the values

Easiest: paste the values into the chat and they'll get set on the Container App directly.

To do it yourself instead, from a machine with the Azure CLI logged in:

```bash
az containerapp update -n ohana-belltown-server -g Ohana --set-env-vars \
  GOOGLE_OAUTH_CLIENT_ID="<client id>" \
  GOOGLE_OAUTH_CLIENT_SECRET="<client secret>"

az containerapp update -n ohana-belltown-server -g Ohana --set-env-vars \
  APPLE_OAUTH_CLIENT_ID="<services id>" \
  APPLE_OAUTH_TEAM_ID="<team id>" \
  APPLE_OAUTH_KEY_ID="<key id>" \
  APPLE_OAUTH_PRIVATE_KEY="<full .p8 file contents>"

az containerapp update -n ohana-belltown-server -g Ohana --set-env-vars \
  FACEBOOK_OAUTH_APP_ID="<app id>" \
  FACEBOOK_OAUTH_APP_SECRET="<app secret>"
```

No redeploy or code change is needed — the server reads these at request
time, so sign-in works as soon as the update finishes (usually under a
minute).

## Verifying it worked

Visit `/signup` or `/login` and click "Continue with Google". If it's
configured correctly you'll be taken to Google's real sign-in page instead
of seeing a `503` error. (Apple's and Facebook's buttons are hidden until
you've set up their credentials — see the note above on re-enabling them.)
