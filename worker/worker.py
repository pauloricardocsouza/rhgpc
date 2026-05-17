"""
R2 People · OCR Worker (Sessão E4)
=====================================================================
Servidor FastAPI que recebe upload de PDFs do Domínio e processa via
pipeline OCR estabelecido na sessão anterior:

    pdftoppm 300 DPI → tesseract por → parser regex/crop → JSON

Pipeline assíncrono:
    1. Cliente faz POST /upload com (multipart PDF, job_id, worker_token)
       Já espera-se que o backend principal tenha criado o job via
       rpc_import_job_create. O cliente passa adiante o job_id e o token.
    2. Worker responde 202 e processa em background
    3. Cliente acompanha via GET /jobs/:id/stream (SSE)
    4. Worker chama de volta o backend Supabase usando worker_token
       para reportar progresso e empurrar items extraídos

Endpoints:
    POST /upload                 · multipart upload do PDF
    GET  /jobs/{job_id}/stream   · SSE com eventos de progresso
    GET  /health                 · liveness probe

Configuração via env:
    SUPABASE_URL          · ex: https://abc.supabase.co
    SUPABASE_ANON_KEY     · chave anon (worker é anon + token)
    WORKER_PORT           · default 8787
    WORKER_TMP_DIR        · default /tmp/r2-worker

Para rodar local em produção:
    pip install fastapi uvicorn httpx python-multipart pillow
    apt install tesseract-ocr tesseract-ocr-por poppler-utils
    uvicorn worker:app --host 0.0.0.0 --port 8787
"""

import os
import re
import json
import asyncio
import shutil
import subprocess
import tempfile
import logging
from pathlib import Path
from typing import Any
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, UploadFile, File, Form, BackgroundTasks, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(level=logging.INFO, format='%(asctime)s · %(levelname)s · %(message)s')
log = logging.getLogger('r2-worker')

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SUPABASE_URL = os.getenv('SUPABASE_URL', 'http://localhost:54321')
SUPABASE_ANON_KEY = os.getenv('SUPABASE_ANON_KEY', '')
TMP_DIR = Path(os.getenv('WORKER_TMP_DIR', '/tmp/r2-worker'))
TMP_DIR.mkdir(parents=True, exist_ok=True)

# Estado em memória dos jobs em execução (para o SSE consultar)
# Em produção, troque por Redis para suportar múltiplas réplicas do worker.
JOB_STATE: dict[str, dict[str, Any]] = {}

# Bbox para crops de nome e beneficiários (espelha o parser do extrator)
BBOX_NOME = (40, 410, 1110, 475)
BBOX_BENEFICIARIOS = (1135, 410, 2400, 475)

# Regexes
DATE_RE = r'\d{2}/\d{2}/\d{4}'
CPF_RE = r'\d{3}\.\d{3}\.\d{3}-\d{2}'
CNPJ_RE = r'\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}'
CEP_RE = r'\d{5}-\d{3}'


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Sanity-check de dependências
    for cmd in ('tesseract', 'pdftoppm'):
        if not shutil.which(cmd):
            log.error(f'Comando ausente: {cmd}')
    log.info(f'Worker iniciado · SUPABASE_URL={SUPABASE_URL}')
    yield
    log.info('Worker encerrando')


app = FastAPI(lifespan=lifespan, title='R2 People OCR Worker')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_methods=['*'],
    allow_headers=['*'],
)


# ---------------------------------------------------------------------------
# Helpers · chamadas ao Supabase via worker_token
# ---------------------------------------------------------------------------

async def supabase_rpc(name: str, params: dict) -> dict:
    """Chama uma RPC pública do Supabase usando a chave anon do worker.
    O escopo é validado por worker_token dentro da própria RPC."""
    if not SUPABASE_ANON_KEY:
        # Modo standalone (sem Supabase) · útil em testes locais
        log.warning(f'Sem SUPABASE_ANON_KEY · pulando RPC {name}')
        return {'ok': True, 'mock': True}
    url = f'{SUPABASE_URL}/rest/v1/rpc/{name}'
    headers = {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': f'Bearer {SUPABASE_ANON_KEY}',
        'Content-Type': 'application/json',
    }
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.post(url, headers=headers, json=params)
        if r.status_code >= 400:
            log.error(f'RPC {name} falhou: {r.status_code} · {r.text[:300]}')
            return {'error': f'http_{r.status_code}', 'detail': r.text[:300]}
        return r.json()


def _emit(job_id: str, kind: str, **data):
    """Adiciona um evento à fila SSE do job."""
    queue: asyncio.Queue = JOB_STATE.setdefault(job_id, {}).setdefault('queue', asyncio.Queue())
    queue.put_nowait({'event': kind, **data})


async def _upload_pdf_to_storage(job_id: str, worker_token: str, pdf_path: Path) -> None:
    """Sessao E5 · faz upload do PDF original para o bucket import-pdfs.
    1. Pega o tenant_id via rpc_import_worker_get_job_meta
    2. Faz PUT no Storage REST API
    3. Chama rpc_import_worker_set_pdf_storage com o path
    Falhas nao abortam o job · so logam e seguem em frente.
    """
    if not SUPABASE_ANON_KEY:
        log.warning(f'Sem SUPABASE_ANON_KEY · pulando upload do PDF de {job_id}')
        return

    try:
        # 1. Tenant id + path template
        meta = await supabase_rpc('rpc_import_worker_get_job_meta', {
            'p_job_id': job_id,
            'p_worker_token': worker_token,
        })
        if 'error' in meta:
            log.error(f'Nao foi possivel obter meta do job {job_id}: {meta}')
            return
        storage_path = meta['storage_path_template']

        # 2. Upload via Storage REST API
        # Em Supabase real: POST /storage/v1/object/import-pdfs/<path> com Authorization Bearer
        url = f'{SUPABASE_URL}/storage/v1/object/import-pdfs/{storage_path}'
        headers = {
            'apikey': SUPABASE_ANON_KEY,
            'Authorization': f'Bearer {SUPABASE_ANON_KEY}',
            'Content-Type': 'application/pdf',
            'x-upsert': 'true',  # idempotente em caso de retry
        }
        pdf_bytes = pdf_path.read_bytes()
        async with httpx.AsyncClient(timeout=120.0) as client:
            r = await client.post(url, headers=headers, content=pdf_bytes)
            if r.status_code >= 400:
                log.error(f'Upload do PDF falhou: {r.status_code} · {r.text[:300]}')
                return

        # 3. Registra o path no job
        result = await supabase_rpc('rpc_import_worker_set_pdf_storage', {
            'p_job_id': job_id,
            'p_worker_token': worker_token,
            'p_storage_path': storage_path,
        })
        if 'error' in result:
            log.error(f'Falha ao registrar storage_path: {result}')
        else:
            log.info(f'PDF do job {job_id} salvo em Storage · {storage_path} ({len(pdf_bytes)} bytes)')
    except Exception as e:
        # Upload e best-effort · nao trava o job
        log.exception(f'Erro inesperado no upload do PDF: {e}')


# ---------------------------------------------------------------------------
# OCR pipeline
# ---------------------------------------------------------------------------

def ocr_crop(image_path: Path, bbox: tuple, psm: str = '7') -> str:
    """Roda OCR só na região especificada da imagem."""
    try:
        from PIL import Image
        im = Image.open(image_path)
        crop = im.crop(bbox)
        tmp_crop = image_path.parent / f'__crop_{bbox[0]}_{bbox[1]}.png'
        crop.save(tmp_crop)
        r = subprocess.run(
            ['tesseract', str(tmp_crop), '-', '-l', 'por', '--psm', psm],
            capture_output=True, text=True, timeout=30,
        )
        if r.returncode == 0:
            lines = [l for l in r.stdout.split('\n') if l.strip()]
            return re.sub(r'\s+', ' ', lines[0]).strip() if lines else ''
    except Exception as e:
        log.warning(f'ocr_crop falhou: {e}')
    return ''


def parse_ficha_page(text: str, image_path: Path) -> dict[str, Any]:
    """Parser de uma página da ficha Domínio.

    Espelha (versão reduzida) o parser da sessão anterior. Para o worker
    de produção, o parser completo de `parse_fichas.py` pode ser importado.
    """
    result: dict[str, Any] = {}
    lines = [l for l in text.split('\n') if l.strip()]

    # ----- Crop OCR para nome + beneficiários (preciso) ------------------
    nome = ocr_crop(image_path, BBOX_NOME, psm='7')
    benef = ocr_crop(image_path, BBOX_BENEFICIARIOS, psm='7')
    if nome:
        result['full_name'] = nome
    if benef:
        cleaned = re.sub(r'[|\\/]', '', benef).strip()
        if not re.search(r'benef[íi]ci', cleaned, re.IGNORECASE) and len(cleaned) >= 10:
            result['beneficiaries'] = cleaned

    # ----- CPF (busca global) -------------------------------------------
    for ln in lines:
        m = re.search(CPF_RE, ln)
        if m:
            result['cpf'] = m.group(0)
            break

    # ----- Matrícula + número da ficha ----------------------------------
    for i, ln in enumerate(lines):
        if 'Matrícula' in ln or 'Matricula' in ln:
            if i + 1 < len(lines):
                m = re.match(r'(\d+)\s+(\d+)', lines[i + 1].strip())
                if m:
                    result['matricula_esocial'] = m.group(1)
            break

    # ----- Cargo + CBO --------------------------------------------------
    for i, ln in enumerate(lines):
        if re.match(r'^Cargo\b', ln) and 'CBO' in ln and i + 1 < len(lines):
            nxt = lines[i + 1].strip()
            cbo_m = re.search(r'(\d{6})\s*$', nxt)
            if cbo_m:
                result['cbo'] = cbo_m.group(1)
                result['job_title'] = re.sub(r'\s+', ' ', nxt[:cbo_m.start()]).strip()
            else:
                result['job_title'] = nxt
            break

    # ----- Admissão + salário inicial ----------------------------------
    for i, ln in enumerate(lines):
        if re.match(r'Data de Admiss[ãa]o', ln) and i + 1 < len(lines):
            nxt = lines[i + 1].strip()
            d = re.search(DATE_RE, nxt)
            if d:
                # DD/MM/AAAA -> AAAA-MM-DD
                dd, mm, yyyy = d.group(0).split('/')
                result['hire_date'] = f'{yyyy}-{mm}-{dd}'
            sal = re.search(r'R\$\s*([\d.]+,\d{2})', nxt)
            if sal:
                v = sal.group(1).replace('.', '').replace(',', '.')
                try:
                    result['initial_salary'] = float(v)
                except ValueError:
                    pass
            break

    # ----- Data de saída -----------------------------------------------
    for ln in lines:
        m = re.search(r'Data da sa[íi]da:\s*(' + DATE_RE + r')', ln)
        if m:
            dd, mm, yyyy = m.group(1).split('/')
            result['termination_date'] = f'{yyyy}-{mm}-{dd}'
            break

    # ----- Data de nascimento ------------------------------------------
    for i, ln in enumerate(lines):
        if re.match(r'Data de nascimento', ln) and i + 1 < len(lines):
            d = re.search(DATE_RE, lines[i + 1])
            if d:
                dd, mm, yyyy = d.group(0).split('/')
                result['birth_date'] = f'{yyyy}-{mm}-{dd}'
            break

    return result


def compute_confidence(payload: dict, alerts: list[str]) -> int:
    """Heurística simples: 100 - 10 * len(alerts) - 5 por campo crítico vazio."""
    critical = ['full_name', 'cpf', 'hire_date', 'job_title']
    score = 100
    score -= 10 * len(alerts)
    for c in critical:
        if not payload.get(c):
            score -= 5
    return max(0, min(100, score))


def compute_alerts(payload: dict) -> list[str]:
    """Lista os alertas para revisão humana baseado no payload extraído."""
    alerts = []
    if not payload.get('cpf'):
        alerts.append('cpf_vazio')
    if not payload.get('full_name'):
        alerts.append('nome_vazio')
    if not payload.get('hire_date'):
        alerts.append('admissao_vazia')
    if not payload.get('job_title'):
        alerts.append('cargo_vazio')
    if not payload.get('birth_date'):
        alerts.append('nascimento_vazio')
    # Suspeita de concatenação de nome + beneficiário
    if payload.get('full_name') and len(payload['full_name'].split()) > 6:
        alerts.append('nome_muito_longo')
    return alerts


# ---------------------------------------------------------------------------
# Background processing
# ---------------------------------------------------------------------------

async def process_pdf(job_id: str, worker_token: str, pdf_path: Path):
    """Processa o PDF inteiro em background. Empurra items e progresso ao Supabase."""
    work_dir = TMP_DIR / job_id
    work_dir.mkdir(parents=True, exist_ok=True)

    try:
        # Conta páginas
        info = subprocess.run(
            ['pdfinfo', str(pdf_path)],
            capture_output=True, text=True, timeout=30,
        )
        pages_total = 0
        for ln in info.stdout.splitlines():
            if ln.startswith('Pages:'):
                pages_total = int(ln.split(':')[1].strip())
                break

        _emit(job_id, 'started', pages_total=pages_total)
        await supabase_rpc('rpc_import_worker_update_job', {
            'p_job_id': job_id,
            'p_worker_token': worker_token,
            'p_patch': {'status': 'running', 'pages_total': pages_total},
        })

        # Renderiza todas as páginas
        subprocess.run(
            ['pdftoppm', '-png', '-r', '300', str(pdf_path), str(work_dir / 'page')],
            check=True, timeout=600,
        )

        items_batch: list[dict] = []
        BATCH_SIZE = 10

        page_files = sorted(work_dir.glob('page-*.png'))
        for idx, page_png in enumerate(page_files, start=1):
            try:
                # OCR full-page
                ocr_out = subprocess.run(
                    ['tesseract', str(page_png), '-', '-l', 'por', '--psm', '6'],
                    capture_output=True, text=True, timeout=120,
                )
                text = ocr_out.stdout

                payload = parse_ficha_page(text, page_png)
                alerts = compute_alerts(payload)
                confidence = compute_confidence(payload, alerts)

                items_batch.append({
                    'page_number': idx,
                    'confidence': confidence,
                    'alerts': alerts,
                    'payload': payload,
                })

                _emit(job_id, 'page', page=idx, total=pages_total,
                      name=payload.get('full_name', '(sem nome)'),
                      confidence=confidence,
                      alerts=alerts)

                # Push em batches para reduzir overhead de rede
                if len(items_batch) >= BATCH_SIZE:
                    await supabase_rpc('rpc_import_worker_push_items', {
                        'p_job_id': job_id,
                        'p_worker_token': worker_token,
                        'p_items': items_batch,
                    })
                    await supabase_rpc('rpc_import_worker_update_job', {
                        'p_job_id': job_id,
                        'p_worker_token': worker_token,
                        'p_patch': {'pages_processed': idx},
                    })
                    items_batch.clear()

            except Exception as e:
                log.exception(f'Página {idx} falhou')
                _emit(job_id, 'page_error', page=idx, error=str(e))

        # Flush final
        if items_batch:
            await supabase_rpc('rpc_import_worker_push_items', {
                'p_job_id': job_id,
                'p_worker_token': worker_token,
                'p_items': items_batch,
            })

        # Sobe o PDF para Storage (sessao E5) · preserva original por 30d apos archive
        await _upload_pdf_to_storage(job_id, worker_token, pdf_path)

        # Marca como completed
        await supabase_rpc('rpc_import_worker_update_job', {
            'p_job_id': job_id,
            'p_worker_token': worker_token,
            'p_patch': {'status': 'completed', 'pages_processed': pages_total},
        })

        _emit(job_id, 'completed', pages_processed=pages_total)
        log.info(f'Job {job_id} concluído · {pages_total} páginas')

    except Exception as e:
        log.exception('Job falhou')
        await supabase_rpc('rpc_import_worker_update_job', {
            'p_job_id': job_id,
            'p_worker_token': worker_token,
            'p_patch': {'status': 'failed', 'error_log': [str(e)]},
        })
        _emit(job_id, 'failed', error=str(e))
    finally:
        # Limpa arquivos temporários
        try:
            shutil.rmtree(work_dir, ignore_errors=True)
            pdf_path.unlink(missing_ok=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get('/health')
async def health():
    return {
        'ok': True,
        'tesseract': shutil.which('tesseract') is not None,
        'pdftoppm': shutil.which('pdftoppm') is not None,
        'active_jobs': len([j for j in JOB_STATE if 'queue' in JOB_STATE[j]]),
    }


@app.post('/upload')
async def upload_pdf(
    background: BackgroundTasks,
    job_id: str = Form(...),
    worker_token: str = Form(...),
    pdf: UploadFile = File(...),
):
    """Recebe o PDF, salva em disco e agenda processamento em background.
    Retorna imediatamente para o cliente poder começar a escutar o SSE."""

    if not pdf.filename or not pdf.filename.lower().endswith('.pdf'):
        raise HTTPException(400, 'Arquivo precisa ser .pdf')

    # Salva o upload em disco
    pdf_path = TMP_DIR / f'{job_id}.pdf'
    size = 0
    with pdf_path.open('wb') as f:
        while chunk := await pdf.read(8192):
            size += len(chunk)
            f.write(chunk)
            if size > 500 * 1024 * 1024:
                pdf_path.unlink(missing_ok=True)
                raise HTTPException(413, 'PDF maior que 500MB')

    log.info(f'Upload recebido · job_id={job_id} · size={size}')

    background.add_task(process_pdf, job_id, worker_token, pdf_path)

    return JSONResponse({'ok': True, 'job_id': job_id, 'size': size}, status_code=202)


@app.get('/jobs/{job_id}/stream')
async def stream_progress(job_id: str):
    """Server-Sent Events com progresso do job.
    O cliente abre uma EventSource(); cada evento vem como JSON serializado."""

    async def event_gen():
        queue: asyncio.Queue = JOB_STATE.setdefault(job_id, {}).setdefault('queue', asyncio.Queue())
        # Mantém a conexão até receber completed/failed
        while True:
            try:
                evt = await asyncio.wait_for(queue.get(), timeout=30.0)
                yield f'event: {evt.get("event", "tick")}\ndata: {json.dumps(evt)}\n\n'
                if evt.get('event') in ('completed', 'failed'):
                    break
            except asyncio.TimeoutError:
                # Heartbeat para keep-alive
                yield ': heartbeat\n\n'

    return StreamingResponse(event_gen(), media_type='text/event-stream', headers={
        'Cache-Control': 'no-cache',
        'X-Accel-Buffering': 'no',  # nginx
    })


if __name__ == '__main__':
    import uvicorn
    uvicorn.run('worker:app', host='0.0.0.0', port=int(os.getenv('WORKER_PORT', 8787)))
