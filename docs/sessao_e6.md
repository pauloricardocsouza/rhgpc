# Sessão E6 · Preview do PDF na tela de revisão

Permite ao RH abrir o PDF original do Domínio em modal full-screen direto na tela de revisão, com zoom, navegação por página e auto-foco na página do item clicado.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Layout | Pop-up modal (não split view nem inline) | Mais flexível: usuário foca no PDF quando precisa, sem comprometer o espaço da lista |
| Escopo | PDF completo com viewer completo | Auditor pode querer ver páginas vizinhas, contexto, capa |
| Tecnologia | `react-pdf` (wrapper de pdf.js) | Mais completo: zoom, scroll, navegação por página, scroll virtual; lida com worker do pdf.js automaticamente |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| Modal viewer | `src/components/imports/PdfPreviewModal.tsx` | 380 |
| Integração na revisão | `src/app/pessoas/importar/[jobId]/page.tsx` | +20 |
| package.json deps | `package.json.example` | +3 |

**Sem mudança de backend.** A signed URL é reaproveitada da `Imports.getPdfUrl` da E5.

## Como funciona

1. RH na tela de revisão (`/pessoas/importar/[jobId]`) clica no ícone de **lupa** em qualquer item
2. Modal abre com `initialPage = item.page_number`
3. Componente busca signed URL de 24h via `Imports.getPdfUrl(jobId)` → `supabase.storage.from(bucket).createSignedUrl(path, 86400)`
4. `react-pdf` carrega o PDF e renderiza diretamente a página do item
5. Toolbar oferece: zoom +/-, ir para página específica, navegação anterior/próxima, abrir em nova aba para download

## Comportamento

**Toolbar:**
- Botão fechar (X) · também fecha com tecla Esc
- Nome do arquivo
- Navegação: input numérico de página + setas anterior/próxima (← e →)
- Zoom: 50%-300% em passos de 25%, botão "100%" reseta
- Download: abre em nova aba (signed URL com `download=`)

**Atalhos:**
- `Esc` fecha
- `←` / `→` navega entre páginas
- `+` / `-` zoom in/out

**Estados:**
- Loading da signed URL · spinner
- Loading do documento · spinner separado
- Loading por página · spinner inline
- Erro `pdf_not_stored` → "PDF não foi salvo no servidor"
- Erro `pdf_purged` → "PDF apagado pelo housekeeping"
- Erro de carga de `react-pdf` → instrução para instalar `npm install react-pdf pdfjs-dist`

**Lupa no item:**
- Sempre disponível (mesmo após aprovar/rejeitar) · permite reconferir
- Tooltip: "Ver página X do PDF original"
- Ícone: `Search` do lucide-react

## Carregamento dinâmico do react-pdf

O componente importa `react-pdf` dinamicamente para:
1. Não quebrar SSR (pdf.js depende de APIs do browser)
2. Permitir build mesmo se o pacote não estiver instalado (degrada graciosamente com mensagem amigável)

Worker do pdf.js é configurado via CDN (`unpkg.com/pdfjs-dist@<version>/build/pdf.worker.min.mjs`). Em produção, recomenda-se hospedar o worker no `/public` do Next.js e ajustar o `workerSrc`.

## Dependências adicionadas

```json
"dependencies": {
  "pdfjs-dist": "^4.0.0",
  "react-pdf": "^7.7.0",
  ...
}
```

Em ambiente sem essas libs, o modal exibe mensagem amigável e o resto da tela continua funcional.

## Validação

```bash
tsc --noEmit --strict
# exit 0 · zero erros (com @ts-expect-error no import dinâmico)
```

## Permissões

Reutiliza `Imports.getPdfUrl` da E5, portanto:
- Qualquer usuário do tenant pode previsualizar (mesmas regras de `employees_can_read`)
- Cross-tenant é bloqueado pelo RLS
- Job com PDF não salvo / purgado → mensagem clara

## Próximos passos

- **E7** · Fallback Vision LLM em items com confidence <50% · usa a signed URL para baixar a página específica e re-extrair
- **E8** · Highlight nas regiões do PDF que o OCR usou (bounding boxes do nome, CPF, etc) sobre a página
- **D1** · Supabase Auth real (libera o sistema para deploy)
