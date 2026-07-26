# Setting Up Google & Apple Sign-In

Both providers are fully built and live in the site's UI already — the
"Continue with Google" / "Continue with Apple" buttons appear on `/signup`,
`/account-login`, `/login`, and `/account.html` — but clicking them returns a
`503 Service Unavailable` until real credentials are set on the Container App.
This doc walks through getting those credentials for both.

Customers can use either provider to sign in self-serve. Staff can only
*link* an existing username/password account to Google/Apple from
`/account.html` — they can't create a brand-new staff account through OAuth.

Once you have the values below, send them over (or set them yourself — see
[Applying the values](#applying-the-values)) and Google/Apple sign-in goes
live immediately, no redeploy needed.

## Google (free, ~10 minutes)

1. Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a new project, or pick an existing one, from the project dropdown at the top of the page.
2. In the left sidebar, go to **APIs & Services → OAuth consent screen**. If you haven't configured this before:
   - User type: **External**
   - Fill in the basic app info (app name, support email, developer contact email) — no Google verification review is needed for a small user base like this.
3. Go to **APIs & Services → Credentials** → **Create Credentials → OAuth client ID**.
   - Application type: **Web application**
   - Name it whatever you like (e.g. "Ohana Belltown Web")
4. Under **Authorized redirect URIs**, add these two exactly:
   - `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/auth/google/customer/callback`
   - `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/auth/google/staff/callback`
   - Optional, for testing locally: also add `http://localhost:8080/auth/google/customer/callback` and `http://localhost:8080/auth/google/staff/callback`
5. Click **Create**. Google shows you a **Client ID** and **Client Secret** — copy both.

These become:
- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`

## Apple (has a real cost — $99/year Apple Developer Program)

1. Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/) if you haven't already. This is a paid, once-a-year membership; there's no way around the cost for Sign in with Apple.
2. Once enrolled, go to [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list) (**Certificates, IDs & Profiles → Identifiers**):
   - If you don't already have an **App ID** for the site, register one, and make sure the **Sign in with Apple** capability is checked.
   - Then register a **Services ID** — this is a second, separate identifier (e.g. `com.ohanabelltown.web`). This Services ID string is your `APPLE_OAUTH_CLIENT_ID`.
   - Configure the Services ID's "Sign in with Apple" settings with:
     - Domain: `ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io`
     - Return URLs:
       - `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/auth/apple/customer/callback`
       - `https://ohana-belltown-server.thankfulwater-0725e291.centralus.azurecontainerapps.io/auth/apple/staff/callback`
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
```

No redeploy or code change is needed — the server reads these at request
time, so sign-in works as soon as the update finishes (usually under a
minute).

## Verifying it worked

Visit `/signup` or `/login` and click "Continue with Google" (or Apple). If
it's configured correctly you'll be taken to the provider's real sign-in
page instead of seeing a `503` error.
