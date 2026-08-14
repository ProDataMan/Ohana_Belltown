# Setting Up Google, Apple & Facebook Sign-In

All three providers are fully built underneath, but clicking a button
returns a `503 Service Unavailable` until real credentials are set on the
Container App. This doc walks through getting those credentials for each.

The "Continue with Google" button appears on `/signup`, `/account-login`,
`/login`, and `/account.html`. Apple's and Facebook's buttons are currently
**hidden** site-wide (via a `hidden` attribute in each page's HTML, or a
`hidden` attribute on the JS-generated link button on `/account.html`) since
neither is configured yet — once you have real credentials for one, remove
the `hidden` attribute from its `.oauth-btn-apple` / `.oauth-btn-facebook`
elements in `customer/signup.html`, `customer/account-login.html`,
`staff/login.html`, and (for the staff account-linking button) `account.js`
to bring it back.

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

1. Go to [developers.facebook.com/apps](https://developers.facebook.com/apps/) and create a new app (choose the "Consumer" or "None" use case — no business verification is needed for basic Facebook Login).
2. From the app dashboard, add the **Facebook Login** product.
3. Under **Facebook Login → Settings**, add this to **Valid OAuth Redirect URIs** — both customer and staff sign-in share it, dispatched internally by the app, same as Google:
   - `https://www.ohanasushigrill.com/auth/facebook/callback`
   - Optional, for testing locally: also add `http://localhost:8080/auth/facebook/callback`
4. Under **App Settings → Basic**, copy the **App ID** and **App Secret**.
5. While the app is in **Development Mode**, only accounts added as testers/admins under **App Roles** can sign in. Switch the app to **Live** (Basic Settings requires a privacy policy URL — `/privacy` already works for this) once you want anyone to be able to use it.

These become:
- `FACEBOOK_OAUTH_APP_ID`
- `FACEBOOK_OAUTH_APP_SECRET`

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
