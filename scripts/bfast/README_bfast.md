# Pipeline BFAST para detecção de início/fim de mineração

## Arquivos

- **`bfast_funcoes.R`** — funções modulares (carregadas com `source()`).
  Contém: `make_gfw_long`, `processa_K_bruto`, `preparar_mensal`,
  `rodar_bfast`, `extrair_inicio_fim`, `estimar_uma_pista`.

- **`bfast_analise.R`** — script principal. Roda o pipeline em todas as
  pistas, gera a tabela final com estimativas, faz comparação com a
  verdade-de-campo (vline_inicio / vline_fim) e teste de Wilcoxon.

- **`bfast_diagnostico_visual.R`** — gera, para cada pista, um painel
  com a curva cumulativa + taxa mensal + vlines (verdade vs. BFAST).
  Essencial para validar visualmente uma amostra antes de confiar nos
  resultados agregados.


## Dependências

```r
install.packages(c("sf", "dplyr", "tidyr", "lubridate", "purrr",
                   "ggplot2", "cowplot", "bfast"))
```

Versão mínima do `bfast`: **1.6.0** (quando `bfastlite()` foi introduzido).
Versão atual recomendada: 1.7.x.


## Ordem de execução

```r
# 1. Roda o pipeline e gera a tabela final + estatísticas
source("bfast_analise.R")

# 2. Gera diagnósticos visuais de uma amostra (recomendado!)
source("bfast_diagnostico_visual.R")
```


## Parâmetros principais (em `PARAMS` no `bfast_analise.R`)

| Parâmetro | Default | O que controla |
|---|---|---|
| `data_inicio` | "2016-01-01" | Início da série temporal |
| `dist_max` | 6000 m | Raio máximo para considerar detecção (mesmo do código original) |
| `Ks` | c(1, 4) | Valores de K a rodar em paralelo |
| `min_meses_ativos` | 6 | Mínimo de meses com taxa > 0 para tentar BFAST |
| `h_min` | 0.1 | Fração mínima de cada segmento (~12 meses em 10 anos) |
| `frac_limiar` | 0.05 | Limiar de "ativo": 5% do P95 da taxa |
| `janela_concord_d` | 180 dias | Janela para concordância K=1 vs K=4 |


## O que esperar nos resultados

`tabela_final` tem uma linha por pista, com:

- `inicio_est_K1`, `fim_est_K1`, `inicio_est_K4`, `fim_est_K4` — datas
  estimadas por BFAST em cada K.
- `status_K1`, `status_K4` — diagnóstico de cada estimativa:
  - `fase_completa` — detectou início E fim (mineração começou e parou)
  - `ativa_em_curso` — detectou início mas atividade continua até hoje
  - `ativa_sem_quebras` — taxa alta, mas sem mudança estrutural detectável
  - `sem_atividade` — taxa baixa demais
  - `atividade_muito_curta` — < `min_meses_ativos` meses ativos
  - `poucas_deteccoes` — < 3 dias com detecção
- `inicio_estimado`, `fim_estimado` — estimativa final (K=1 prioritário,
  K=4 como fallback). Esta é a coluna principal para análises.
- `fonte_inicio`, `fonte_fim` — "K1" ou "K4", para rastreabilidade.
- `lag_inicio_dias`, `lag_fim_dias` — defasagem em dias.
  Negativo = BFAST detectou antes da verdade-de-campo.


## Casos de borda já tratados

- Pistas com 0 detecções → `status = poucas_deteccoes`, sem erro.
- Pistas com atividade contínua (sem fim) → `fim_estimado = NA`,
  `status = ativa_em_curso`.
- Pistas que já começam ativas em 2016 → `inicio_est = 2016-01-01`,
  `status = fase_completa` se houver fim depois.
- Pistas onde `bfastlite` não converge → captura erro, marca `erro:...`.


## Recomendações de uso

1. **Rode o diagnóstico visual em uma amostra primeiro** (~20 pistas).
   Veja se os breakpoints fazem sentido. Se 80%+ parecerem corretos,
   confie no agregado.

2. **Calibre `frac_limiar` se necessário.** Se BFAST está marcando
   "ativo" segmentos visualmente em platô, aumente para 0.08–0.10. Se
   está perdendo atividade real fraca, reduza para 0.02–0.03.

3. **Calibre `h_min` se quiser detectar fases mais curtas.** Default
   `0.1` evita segmentos < 12 meses. Se você espera mineração de 6
   meses, use `0.05`.

4. **Reporte a tabela de concordância K=1/K=4** no seu trabalho. É uma
   métrica de robustez que reviewers vão pedir.

5. **Sinalize as pistas que começam com `area > 0` em 2016** como
   "início anterior à janela de observação" — não tente forçar uma data
   inicial para elas.
