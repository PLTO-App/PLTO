import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';
const SUPABASE_URL           = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// Verify Stripe signature
async function verifyStripeSignature(payload: string, sig: string, secret: string) {
  const parts   = sig.split(',').reduce((acc: Record<string, string>, p) => {
    const [k, v] = p.split('='); acc[k] = v; return acc;
  }, {});
  const ts      = parts['t'];
  const v1      = parts['v1'];
  const signed  = `${ts}.${payload}`;
  const key     = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sigBuf  = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(signed));
  const computed = Array.from(new Uint8Array(sigBuf)).map(b => b.toString(16).padStart(2, '0')).join('');
  return computed === v1;
}

// Plan mapping from Stripe Price ID → our plan name
// Fill these in after creating products in Stripe Dashboard:
const PRICE_TO_PLAN: Record<string, string> = {
  'REPLACE_PRICE_ID_BASIC':   'basic',
  'REPLACE_PRICE_ID_PRO':     'pro',
  'REPLACE_PRICE_ID_PREMIUM': 'premium',
};

serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const payload = await req.text();
  const sig     = req.headers.get('stripe-signature') ?? '';

  // Verify webhook authenticity
  if (STRIPE_WEBHOOK_SECRET) {
    const valid = await verifyStripeSignature(payload, sig, STRIPE_WEBHOOK_SECRET);
    if (!valid) return new Response('Invalid signature', { status: 400 });
  }

  const event = JSON.parse(payload);
  const sb    = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  if (event.type === 'checkout.session.completed') {
    const session    = event.data.object;
    const tenantId   = session.client_reference_id;   // passed from our app
    const customerId = session.customer;
    const subId      = session.subscription;
    const priceId    = session.line_items?.data?.[0]?.price?.id
                    || session.metadata?.price_id;

    if (!tenantId) {
      console.error('No client_reference_id in session');
      return new Response('Missing tenant', { status: 400 });
    }

    const plan = PRICE_TO_PLAN[priceId] ?? 'basic';

    await sb.from('tenants').update({
      plan,
      stripe_customer_id:      customerId,
      stripe_subscription_id:  subId,
      trial_ends_at:           null,   // clear trial — now on paid plan
    }).eq('id', tenantId);

    console.log(`Tenant ${tenantId} upgraded to ${plan}`);
  }

  if (event.type === 'customer.subscription.deleted') {
    const sub        = event.data.object;
    const customerId = sub.customer;

    await sb.from('tenants')
      .update({ plan: 'cancelled', stripe_subscription_id: null })
      .eq('stripe_customer_id', customerId);

    console.log(`Subscription cancelled for customer ${customerId}`);
  }

  if (event.type === 'invoice.payment_failed') {
    const invoice    = event.data.object;
    const customerId = invoice.customer;
    console.warn(`Payment failed for customer ${customerId}`);
    // Optionally: send WhatsApp reminder via Make.com webhook
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
