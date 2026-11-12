UPDATE private.atina_detective_case_templates
SET case_payload=jsonb_set(
  jsonb_set(case_payload,'{intro}',
    to_jsonb('Durante uma tempestade, o faroleiro Duarte Vale foi encontrado morto no antigo farol da Ponta da Névoa. A porta principal estava trancada por dentro. Sete suspeitos estiveram no local nessa noite. Descobre o que aconteceu.'::text),true),
  '{characters}',
  (SELECT jsonb_agg(
    CASE WHEN value->>'key'='bia' THEN
      jsonb_set(value,'{persona}',
        '{"temperament":"direct","statements":{"general":"Não vou inventar uma história para agradar a ninguém.","whereabouts":"Estive na cozinha a preparar café.","timeline":"A luz apagou-se por alguns instantes depois das dez.","relationships":"O Duarte era meu tio."}}'::jsonb,true)
    ELSE value END
    ORDER BY ordinality)
   FROM jsonb_array_elements(case_payload->'characters') WITH ORDINALITY AS x(value,ordinality)
  ),
  true
),
updated_at=clock_timestamp()
WHERE case_id='o-ultimo-farol';
