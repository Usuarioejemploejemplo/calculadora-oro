import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    if (!url || !serviceRoleKey || !publicKey) {
      console.error("Faltan secretos requeridos para login-by-username.");
      return json({ error: "Servicio de acceso no configurado." }, 500);
    }

    const body = await req.json().catch(() => null);
    const username = typeof body?.username === "string" ? body.username.trim().toLowerCase() : "";
    const password = typeof body?.password === "string" ? body.password : "";
    if (!/^[a-z0-9._-]{3,32}$/.test(username) || password.length < 1 || password.length > 256) {
      return json({ error: "Usuario o contraseña incorrectos." }, 401);
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: alias, error: aliasError } = await admin
      .from("login_aliases")
      .select("user_id")
      .eq("username", username)
      .eq("is_active", true)
      .maybeSingle();

    if (aliasError || !alias) return json({ error: "Usuario o contraseña incorrectos." }, 401);

    const { data: authUser, error: userError } = await admin.auth.admin.getUserById(alias.user_id);
    const email = authUser?.user?.email;
    if (userError || !email) return json({ error: "Usuario o contraseña incorrectos." }, 401);

    const publicClient = createClient(url, publicKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: signedIn, error: signInError } = await publicClient.auth.signInWithPassword({
      email,
      password,
    });

    if (signInError || !signedIn.session) {
      return json({ error: "Usuario o contraseña incorrectos." }, 401);
    }

    return json({
      access_token: signedIn.session.access_token,
      refresh_token: signedIn.session.refresh_token,
    });
  } catch (error) {
    console.error("Error inesperado en login-by-username:", error instanceof Error ? error.message : "unknown");
    return json({ error: "No se pudo completar el inicio de sesión." }, 500);
  }
});
