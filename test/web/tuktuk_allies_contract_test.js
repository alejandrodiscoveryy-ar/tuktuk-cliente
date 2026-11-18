const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const html = fs.readFileSync(path.join(root,'web/index.html'),'utf8');
const booking = fs.readFileSync(path.join(root,'lib/presentation/marketplace_customer_booking_flow.dart'),'utf8');

test('personalized ally link tags customer analytics with a distinct namespace',()=>{
  assert.match(html,/params\.get\("aliado"\)/);
  assert.match(html,/"aliado_" \+ ally/);
  assert.match(html,/tuktukImpulsaTrack\("link_open"\)/);
});

test('only server-verified bookings carry the ally slug, without competing Impulsa attribution',()=>{
  assert.match(booking,/final allySlug = kIsWeb \? Uri\.base\.queryParameters\['aliado'\]/);
  assert.match(booking,/if \(_promo == null && validAlly\) 'target_ally_slug': allySlug/);
  assert.match(booking,/customer_impulsa_analytics\.track\('request_created'\)/);
});

test('driver promo remains independent of ally campaign',()=>{
  assert.match(booking,/if \(_promo != null\) 'target_promo_code': _promo!\.code/);
  assert.match(html,/params\.get\("conductor"\)/);
});
