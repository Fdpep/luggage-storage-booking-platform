import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const BUCKET_FALLBACK = "booking-checkin-photos";

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // ✅ protezione: header segreto (oltre al JWT)
  const expected = Deno.env.get("BOOKING_PHOTO_TTL_JOB_SECRET") ?? "";
  const got = req.headers.get("x-job-secret") ?? "";
  if (!expected || got !== expected) {
    return new Response("Unauthorized", { status: 401 });
  }

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const body = await req.json().catch(() => ({}));
  const limit = Math.min(Number(body.limit ?? 200), 500);
  const dryRun = body.dry_run === true;

  const nowIso = new Date().toISOString();

  const { data: rows, error } = await supabase
    .from("partner_bookings")
    .select("id, checkin_photo_bucket, checkin_photo_path")
    .not("checkin_photo_path", "is", null)
    .lte("checkin_photo_expires_at", nowIso)
    .limit(limit);

  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const list = rows ?? [];

  // raggruppa per bucket
  const byBucket = new Map<string, string[]>();
  for (const r of list) {
    const bucket = (r.checkin_photo_bucket as string | null) ?? BUCKET_FALLBACK;
    const path = r.checkin_photo_path as string | null;
    if (!path) continue;
    byBucket.set(bucket, [...(byBucket.get(bucket) ?? []), path]);
  }

  let removedCount = 0;
  const errors: any[] = [];

  if (!dryRun) {
    for (const [bucket, paths] of byBucket.entries()) {
      for (let i = 0; i < paths.length; i += 100) {
        const chunk = paths.slice(i, i + 100);
        const { error: remErr } = await supabase.storage.from(bucket).remove(chunk);
        if (remErr) errors.push({ bucket, error: remErr.message, n: chunk.length });
        else removedCount += chunk.length;
      }
    }

    const ids = list.map((r: any) => r.id);
    if (ids.length) {
      const { error: updErr } = await supabase
        .from("partner_bookings")
        .update({
          checkin_photo_bucket: null,
          checkin_photo_path: null,
          checkin_photo_uploaded_at: null,
          checkin_photo_expires_at: null,
          checkin_photo_uploaded_by: null,
          checkin_photo_deleted_at: new Date().toISOString(),
        })
        .in("id", ids);

      if (updErr) errors.push({ update: updErr.message });
    }
  }

  return new Response(
    JSON.stringify({
      ok: true,
      scanned: list.length,
      dry_run: dryRun,
      removed: dryRun ? 0 : removedCount,
      errors,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
