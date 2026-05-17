-- ============================================================================
-- Setup local · Postgres dev (NAO aplicar em producao Supabase)
-- ============================================================================
-- Cria schema auth, stub auth.uid() lendo de request.jwt.claim.sub,
-- roles anon/authenticated NOLOGIN, helpers de "login" para testes,
-- e stubs minimos do schema storage (bucket/objects) usados pela migration de PDI.
-- Em producao Supabase, tudo isso ja existe nativo.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;

CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_uid TEXT;
BEGIN
  v_uid := current_setting('request.jwt.claim.sub', TRUE);
  IF v_uid IS NULL OR v_uid = '' THEN
    RETURN NULL;
  END IF;
  RETURN v_uid::UUID;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

DO $$ BEGIN
  CREATE ROLE anon NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE ROLE authenticated NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;

-- Helper para os testes (login como auth_user_id)
CREATE OR REPLACE FUNCTION test_login(p_auth_uid UUID)
RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_auth_uid::TEXT, TRUE);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION test_logout()
RETURNS VOID AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', TRUE);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Stubs minimos do schema storage para Postgres local
-- (em Supabase de verdade essas tabelas ja existem com a estrutura completa)
-- ============================================================================

CREATE TABLE IF NOT EXISTS storage.buckets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  owner UUID,
  public BOOLEAN DEFAULT FALSE,
  file_size_limit BIGINT,
  allowed_mime_types TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id TEXT REFERENCES storage.buckets(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  owner UUID,
  metadata JSONB,
  path_tokens TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA storage TO anon, authenticated;
GRANT ALL ON storage.buckets, storage.objects TO authenticated;

-- Replica da funcao do Supabase Storage que retorna o array de pastas do path.
-- Para "tenant_id/plan_id/arquivo.pdf" retorna ARRAY['tenant_id','plan_id'].
CREATE OR REPLACE FUNCTION storage.foldername(name TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_parts TEXT[];
BEGIN
  IF name IS NULL OR name = '' THEN
    RETURN ARRAY[]::TEXT[];
  END IF;
  v_parts := string_to_array(name, '/');
  -- Remove o ultimo elemento (nome do arquivo) · retorna so as pastas
  IF array_length(v_parts, 1) <= 1 THEN
    RETURN ARRAY[]::TEXT[];
  END IF;
  RETURN v_parts[1:array_length(v_parts, 1) - 1];
END;
$$;

GRANT EXECUTE ON FUNCTION storage.foldername(TEXT) TO anon, authenticated;
