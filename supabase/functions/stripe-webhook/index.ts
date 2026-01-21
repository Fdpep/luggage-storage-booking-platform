import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@16.2.0?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4?target=deno";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: "2024-06-20" });
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

serve(async (req) => {
  try {
    if (req.method !== "POST") return new Response("Use POST", { status: 405 });

    const sig = req.headers.get("stripe-signature");
    if (!sig) return new Response("Missing stripe-signature", { status: 400 });

    // IMPORTANTISSIMO: raw body
    const rawBody = await req.text();

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(rawBody, sig, STRIPE_WEBHOOK_SECRET);
    } catch (_err) {
      return new Response("Webhook signature verification failed", { status: 400 });
    }

    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;

      const requestId = session.metadata?.partner_request_id;
      if (!requestId) return new Response("Missing partner_request_id in metadata", { status: 400 });

      const paymentRef = (session.payment_intent as string | null) ?? session.id;

      // Qui assumo che tu abbia questa RPC server-side già pronta (come nel tuo codice)
      const { error } = await admin.rpc("finalize_partner_payment_webhook", {
        p_request_id: requestId,
        p_stripe_session_id: session.id,
        p_payment_reference: paymentRef,
      });

      if (error) return new Response(`RPC error: ${error.message}`, { status: 500 });
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response(`Error: ${(e as any)?.message ?? String(e)}`, { status: 500 });
  }
});
