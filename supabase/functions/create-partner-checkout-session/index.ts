import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@16.2.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4?target=deno";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const PRICE_ID = Deno.env.get("STRIPE_PARTNER_PRICE_ID")!;
const SUCCESS_URL = Deno.env.get("PAYMENT_SUCCESS_URL")!;
const CANCEL_URL = Deno.env.get("PAYMENT_CANCEL_URL")!;

const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });

serve(async (req) => {
  // CORS minimale
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Use POST" }), {
        status: 405,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    // Auth user (JWT Supabase dal browser)
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing Authorization Bearer token" }), {
        status: 401,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Not authenticated" }), {
        status: 401,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const uid = userData.user.id;

    // body: request_id (opzionale)
    const body = await req.json().catch(() => ({}));
    const requestId: string | undefined = body?.request_id;

    // Carica richiesta partner e verifica status
    let q = supabase
      .from("partner_requests")
      .select("id,status,user_id,created_at")
      .eq("user_id", uid)
      .order("created_at", { ascending: false })
      .limit(1);

    if (requestId) {
      q = supabase
        .from("partner_requests")
        .select("id,status,user_id,created_at")
        .eq("id", requestId)
        .limit(1);
    }

    const { data: rows, error: reqErr } = await q;
    if (reqErr) throw reqErr;

    const pr = rows?.[0];
    if (!pr) {
      return new Response(JSON.stringify({ error: "No partner request found" }), {
        status: 404,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }
    if (pr.user_id !== uid) {
      return new Response(JSON.stringify({ error: "Request not yours" }), {
        status: 403,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }
    if (pr.status !== "awaiting_payment") {
      return new Response(JSON.stringify({ error: `Invalid status: ${pr.status}` }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    // Costruzione robusta URL (NO codice dentro l’oggetto Stripe!)
    const success = new URL(SUCCESS_URL);
    success.searchParams.set("success", "1");
    success.searchParams.set("session_id", "{CHECKOUT_SESSION_ID}");

    const cancel = new URL(CANCEL_URL);
    cancel.searchParams.set("cancel", "1");

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [{ price: PRICE_ID, quantity: 1 }],
      success_url: success.toString(),
      cancel_url: cancel.toString(),
      client_reference_id: uid,
      customer_email: userData.user.email ?? undefined,
      metadata: {
        partner_request_id: pr.id,
        supabase_user_id: uid,
      },
    });

    return new Response(JSON.stringify({ url: session.url }), {
      status: 200,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as any)?.message ?? String(e) }), {
      status: 500,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
    });
  }
});
