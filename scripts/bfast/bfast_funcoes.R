# =============================================================================
# bfast_funcoes_v3.R
#
# Mudanças em relação à v2:
#   1. Critério de "ativo" usa DOIS testes combinados:
#        (a) Média absoluta > frac_limiar * max(medias_segs)  [absoluto]
#        (b) NÃO houve queda > queda_rel em relação ao segmento anterior [relativo]
#      Um segmento é "ativo" só se passa nos DOIS.
#      Isso resolve o caso onde o platô tem "ruído de fundo" alto mas é
#      claramente platô comparado ao segmento anterior.
#   2. processa_K_bruto: filtra `pista == id` PRIMEIRO (antes dos outros
#      filtros) para evitar erro de memória em séries longas.
#   3. Mantém todas as correções da v2.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(sf)
  library(bfast)
})

`%||%` <- function(a, b) if (is.null(a)) b else a


# -----------------------------------------------------------------------------
# 1. Pré-processamento: GFW long
# -----------------------------------------------------------------------------
make_gfw_long <- function(GFW_data, pistas_validade) {
  GFW_data %>%
    st_drop_geometry() %>%
    mutate(detect_id = row_number()) %>%
    pivot_longer(
      cols = matches("^(pista|dist)_\\d+$"),
      names_to = c(".value", "rank_orig"),
      names_pattern = "(pista|dist)_(\\d+)"
    ) %>%
    mutate(pista = as.integer(pista)) %>%
    left_join(pistas_validade, by = c("pista" = "id_pista")) %>%
    filter(!is.na(pista)) %>%
    group_by(detect_id) %>%
    arrange(dist, .by_group = TRUE) %>%
    mutate(rank_novo = row_number()) %>%
    ungroup()
}


# -----------------------------------------------------------------------------
# 2. Série bruta de eventos (CORREÇÃO v3: filter por pista PRIMEIRO)
# -----------------------------------------------------------------------------
processa_K_bruto <- function(GFW_long_input, id, K, dist_max = 6000) {
  GFW_long_input %>%
    filter(pista == id) %>%      # filtra essa pista primeiro: reduz o dataset
    filter(
      rank_novo <= K,
      !is.na(dist),
      dist <= dist_max
    ) %>%
    group_by(doy) %>%
    summarise(area_evento = sum(area, na.rm = TRUE), .groups = "drop") %>%
    arrange(doy) %>%
    mutate(
      area_acum = cumsum(area_evento),
      K = K
    )
}


# -----------------------------------------------------------------------------
# 3. Agregação mensal
# -----------------------------------------------------------------------------
preparar_mensal <- function(serie_bruta, data_inicio = "2016-01-01") {
  if (nrow(serie_bruta) == 0) return(NULL)
  
  data_inicio <- as.Date(data_inicio)
  data_fim    <- floor_date(max(serie_bruta$doy), "month")
  meses       <- seq(data_inicio, data_fim, by = "month")
  
  area_em_inicio <- serie_bruta %>%
    filter(doy < data_inicio) %>%
    summarise(s = sum(area_evento, na.rm = TRUE)) %>%
    pull(s)
  comeca_ativa <- area_em_inicio > 0
  
  mensal <- serie_bruta %>%
    filter(doy >= data_inicio) %>%
    mutate(mes = floor_date(doy, "month")) %>%
    group_by(mes) %>%
    summarise(taxa = sum(area_evento, na.rm = TRUE), .groups = "drop") %>%
    right_join(tibble(mes = meses), by = "mes") %>%
    mutate(taxa = replace_na(taxa, 0)) %>%
    arrange(mes)
  
  attr(mensal, "comeca_ativa") <- comeca_ativa
  mensal
}


# -----------------------------------------------------------------------------
# 4. Rodar BFAST Lite
# -----------------------------------------------------------------------------
rodar_bfast <- function(serie_mensal, h_min = 0.05, breaks_method = "BIC") {
  if (is.null(serie_mensal) || nrow(serie_mensal) < 24) return(NULL)
  
  ts_taxa <- ts(
    serie_mensal$taxa,
    start     = c(year(min(serie_mensal$mes)), month(min(serie_mensal$mes))),
    frequency = 12
  )
  
  fit <- tryCatch(
    bfastlite(
      ts_taxa,
      formula = response ~ trend,
      breaks  = breaks_method,
      h       = h_min
    ),
    error = function(e) {
      message("  bfastlite falhou: ", e$message)
      NULL
    }
  )
  fit
}


# -----------------------------------------------------------------------------
# 5. CLASSIFICAÇÃO DE SEGMENTOS (lógica nova v3)
# -----------------------------------------------------------------------------
#
# Um segmento é "ATIVO" se passa nos DOIS critérios:
#   (a) Absoluto: média > frac_limiar * max(medias_segs)
#   (b) Relativo: NÃO houve queda > queda_rel em relação ao segmento anterior
#                 (i.e., media[i] >= queda_rel * media[i-1])
#
# Se houver uma queda grande de um segmento para o próximo, mesmo que a média
# absoluta do segmento ainda esteja alta em termos brutos, classificamos como
# "platô / fim de fase".
#
# Critério (b) só se aplica DEPOIS de ter visto um pico (ou seja, não classifica
# os primeiros segmentos de subida como "queda").

classificar_segmentos <- function(medias, frac_limiar = 0.05, queda_rel = 0.30) {
  if (length(medias) == 0) return(logical(0))
  
  pico <- max(medias)
  if (pico == 0) return(rep(FALSE, length(medias)))
  
  limiar_abs <- frac_limiar * pico
  
  # Critério (a): absoluto
  ativo_abs <- medias > limiar_abs
  
  # Critério (b): relativo — começa válido como TRUE, só fica FALSE depois de
  # um pico se houve queda significativa.
  ativo_rel <- rep(TRUE, length(medias))
  ja_viu_pico <- FALSE
  pico_visto <- 0
  
  for (i in seq_along(medias)) {
    if (medias[i] >= pico * 0.5) {
      ja_viu_pico <- TRUE
      pico_visto <- max(pico_visto, medias[i])
    }
    if (ja_viu_pico && medias[i] < queda_rel * pico_visto) {
      # caiu para menos de queda_rel*100% do maior pico já visto → platô
      ativo_rel[i] <- FALSE
    }
  }
  
  ativo_abs & ativo_rel
}


# -----------------------------------------------------------------------------
# 6. Extrair início e fim
# -----------------------------------------------------------------------------
extrair_inicio_fim <- function(fit, serie_mensal,
                               frac_limiar = 0.05, queda_rel = 0.30) {
  base <- list(
    inicio = as.Date(NA), fim = as.Date(NA),
    n_breakpoints = 0L, status = "sem_quebras",
    medias_segs = NA, limiar_usado = NA_real_
  )
  if (is.null(fit)) return(base)
  
  bps   <- fit$breakpoints$breakpoints
  taxa  <- serie_mensal$taxa
  datas <- serie_mensal$mes
  comeca_ativa <- isTRUE(attr(serie_mensal, "comeca_ativa"))
  
  if (length(bps) == 0 || all(is.na(bps))) {
    pico <- max(taxa)
    media_total <- mean(taxa)
    limiar <- frac_limiar * pico
    if (pico == 0) {
      return(modifyList(base, list(status = "sem_atividade",
                                   limiar_usado = limiar)))
    }
    if (media_total > limiar) {
      return(modifyList(base, list(
        status = if (comeca_ativa) "ativa_pre_2016" else "ativa_sem_quebras",
        inicio = if (comeca_ativa) as.Date(NA) else datas[1],
        fim = as.Date(NA),
        limiar_usado = limiar
      )))
    }
    return(modifyList(base, list(status = "sem_atividade",
                                 limiar_usado = limiar)))
  }
  
  bordas <- c(0, bps, length(taxa))
  medias <- sapply(seq_len(length(bordas) - 1), function(i) {
    mean(taxa[(bordas[i] + 1):bordas[i + 1]])
  })
  
  pico_segs <- max(medias)
  if (pico_segs == 0) {
    return(modifyList(base, list(
      status = "sem_atividade",
      n_breakpoints = length(bps),
      medias_segs = list(medias),
      limiar_usado = 0
    )))
  }
  
  # Classificação NOVA (v3): combina critério absoluto + relativo
  ativo <- classificar_segmentos(medias, frac_limiar, queda_rel)
  
  # Início
  if (ativo[1]) {
    inicio <- if (comeca_ativa) as.Date(NA) else datas[1]
  } else {
    transicoes_up <- which(diff(c(FALSE, ativo)) == 1L)
    if (length(transicoes_up) == 0) {
      inicio <- as.Date(NA)
    } else {
      idx_primeira <- transicoes_up[1]
      inicio <- datas[bordas[idx_primeira] + 1]
    }
  }
  
  # Fim
  transicoes_down <- which(diff(c(ativo, FALSE)) == -1L)
  termina_ativa   <- ativo[length(ativo)]
  
  if (termina_ativa) {
    fim <- as.Date(NA)
    status <- "ativa_em_curso"
  } else if (length(transicoes_down) == 0) {
    fim <- as.Date(NA)
    status <- "indefinido"
  } else {
    idx_ultima <- tail(transicoes_down, 1)
    fim <- datas[bordas[idx_ultima + 1]]
    status <- "fase_completa"
  }
  
  if (comeca_ativa && !is.na(fim)) status <- "ativa_pre_2016_com_fim"
  if (comeca_ativa &&  is.na(fim)) status <- "ativa_pre_2016_em_curso"
  
  list(
    inicio = inicio, fim = fim,
    n_breakpoints = length(bps),
    status = status,
    medias_segs = list(medias),
    limiar_usado = frac_limiar * pico_segs
  )
}


# -----------------------------------------------------------------------------
# 7. Wrapper
# -----------------------------------------------------------------------------
estimar_uma_pista <- function(GFW_long_input, id, K,
                              data_inicio = "2016-01-01",
                              dist_max = 6000,
                              min_meses_ativos = 6,
                              h_min = 0.05,
                              frac_limiar = 0.05,
                              queda_rel = 0.30,
                              breaks_method = "BIC") {
  
  bruto <- processa_K_bruto(GFW_long_input, id, K, dist_max = dist_max)
  
  if (nrow(bruto) < 3) {
    return(tibble(
      id_pista = id, K = K,
      inicio_est = as.Date(NA), fim_est = as.Date(NA),
      n_breakpoints = NA_integer_,
      status = "poucas_deteccoes",
      area_total = sum(bruto$area_evento %||% 0, na.rm = TRUE)
    ))
  }
  
  mensal <- preparar_mensal(bruto, data_inicio = data_inicio)
  
  if (is.null(mensal) || sum(mensal$taxa > 0) < min_meses_ativos) {
    return(tibble(
      id_pista = id, K = K,
      inicio_est = as.Date(NA), fim_est = as.Date(NA),
      n_breakpoints = NA_integer_,
      status = "atividade_muito_curta",
      area_total = sum(bruto$area_evento, na.rm = TRUE)
    ))
  }
  
  fit <- rodar_bfast(mensal, h_min = h_min, breaks_method = breaks_method)
  out <- extrair_inicio_fim(fit, mensal,
                            frac_limiar = frac_limiar, queda_rel = queda_rel)
  
  tibble(
    id_pista = id, K = K,
    inicio_est = out$inicio, fim_est = out$fim,
    n_breakpoints = out$n_breakpoints,
    status = out$status,
    area_total = sum(bruto$area_evento, na.rm = TRUE)
  )
}