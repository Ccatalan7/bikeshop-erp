const { createClient } = require('@supabase/supabase-js');
const dbUrl = process.env.SUPABASE_DB_URL || 'http://127.0.0.1:54321';
const supabase = createClient(process.env.SUPABASE_URL || 'http://127.0.0.1:54321', process.env.SUPABASE_ANON_KEY || 'dummy');
// Or just use node pg
const { Client } = require('pg');
const client = new Client({ connectionString: process.env.SUPABASE_DB_URL || 'postgresql://postgres:postgres@localhost:54322/postgres' });
client.connect().then(() => {
  client.query("SELECT invoice_number, status, total, paid_amount, balance FROM purchase_invoices WHERE invoice_number IN ('FC-00025', 'FC-00023')", (err, res) => {
    console.log(err ? err.stack : res.rows);
    client.end();
  });
});
