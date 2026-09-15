begin;
select no_plan();
\ir fixtures/product_spec_public_inference.sql
\ir fixtures/product_spec_public_inference_assertions.sql
set constraints all immediate;
select * from finish();
rollback;
