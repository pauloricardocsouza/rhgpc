-- ============================================================================
-- R2 People · Seed PDI v1
-- ============================================================================
-- Seed opcional · cria ciclos de exemplo para um tenant.
--
-- ATENCAO · este seed assume que ja existe um tenant. Substitua o UUID
-- abaixo pelo ID do seu tenant antes de rodar.
--
-- Permissoes do PDI ja foram seedadas em r2_people_seed_base_v1.sql:
--   view_self_pdi, manage_self_pdi
--   view_team_pdi, manage_team_pdi
--   view_all_pdi, manage_all_pdi
-- ============================================================================

-- Substitua aqui pelo seu tenant_id real:
--   ex: SELECT id FROM tenants WHERE slug = 'gpc';
DO $$
DECLARE
  v_tenant UUID;
BEGIN
  SELECT id INTO v_tenant FROM tenants ORDER BY created_at LIMIT 1;

  IF v_tenant IS NULL THEN
    RAISE NOTICE 'Nenhum tenant encontrado · pule este seed ate criar um tenant';
    RETURN;
  END IF;

  -- Ciclos do ano corrente e proximo
  INSERT INTO pdi_cycles (tenant_id, code, display_name, start_date, end_date, open_for_planning)
  VALUES
    (v_tenant, '2026-S1', 'Primeiro semestre 2026', '2026-01-01', '2026-06-30', FALSE),  -- ja iniciado
    (v_tenant, '2026-S2', 'Segundo semestre 2026', '2026-07-01', '2026-12-31', TRUE),
    (v_tenant, '2026',    'Ciclo anual 2026',     '2026-01-01', '2026-12-31', TRUE),
    (v_tenant, '2027-S1', 'Primeiro semestre 2027', '2027-01-01', '2027-06-30', TRUE)
  ON CONFLICT (tenant_id, code) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date,
    open_for_planning = EXCLUDED.open_for_planning;

  RAISE NOTICE 'Ciclos criados para tenant %', v_tenant;
END $$;

-- ============================================================================
-- VALIDACAO POS-SEED
-- ============================================================================
-- SELECT count(*) FROM pdi_cycles WHERE active;
--   Esperado: 4 (ou +N por tenant adicional)
--
-- SELECT code, open_for_planning FROM pdi_cycles ORDER BY start_date;
--   2026-S1 · open_for_planning=FALSE (semestre ja iniciado)
--   2026-S2 · open_for_planning=TRUE
--   2026    · open_for_planning=TRUE
--   2027-S1 · open_for_planning=TRUE
-- ============================================================================
