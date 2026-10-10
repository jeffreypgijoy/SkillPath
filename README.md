# SkillPath local setup

The standalone `file_settings.html` demo can be explored without Supabase using the demo-account picker. Email/password sign-in, student profiles, and admin-assigned account roles require a configured Supabase project.

## Configure Supabase

1. Create a Supabase project. Apply the migrations in order: `supabase/migrations/202610090001_skillpath_core.sql`, `supabase/migrations/202610100001_profiles_and_admin_roles.sql`, then `supabase/migrations/202610100002_ai_quota_repair.sql`.
2. Put the project URL and **publishable/anon key** in `supabase-config.js`. This browser-visible key is expected to be public; never put a service-role key or an AI-provider key there.
3. In Supabase Auth, enable email/password sign-in and configure the site's allowed redirect URLs.
4. Create your account through the sign-up form. Every new account is assigned the `student` role by the database.
5. To enable Gemini-backed AI features, install the Supabase CLI, sign in, and link this folder to your project. Set the provider key as an Edge Function secret and deploy the authenticated AI function:

   ```sh
   supabase login
   supabase link --project-ref your-project-ref
   supabase db push
   supabase secrets set GEMINI_API_KEY=your-gemini-api-key
   supabase functions deploy ai-assistant
   ```

   The key is used only by the Edge Function; do not add it to `supabase-config.js` or the HTML. The AI features require an authenticated student account and the deployed function.
   The Resume Analyzer can read text-based PDFs up to 12 MB and 20 pages. PDF text is extracted in the browser and sent to the authenticated Edge Function for Gemini review; scanned/image-only PDFs are not supported.
6. To appoint the first administrator, run this once in the Supabase SQL editor, replacing the address with the account you created:

   ```sql
   update public.profiles
   set role = 'admin'
   where lower(email) = lower('your-admin-email@example.com');
   ```

   Check that exactly one row was updated. After that, authenticated admins can assign `student`, `trainer`, or `admin` roles from Admin Console → User roles. The database rejects role changes made by non-admins and prevents admins from changing their own role.
7. Serve this folder over HTTP (not `file://`):

   ```sh
   python3 -m http.server 8000
   ```

   Open `http://localhost:8000/file_settings.html`.

Without project credentials, email/password sign-in is unavailable but the demo-account picker still works. The demo admin persona is only for showcasing and cannot assign real account roles. Never put a service-role key or an AI-provider secret in `supabase-config.js` or browser settings.
