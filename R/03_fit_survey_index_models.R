# ============================================================
# COMPONENT 3: Survey index modelling
# ============================================================

survey_design_ids <- function(weight, psu = NULL, strata = NULL) {
  list(weight = weight, psu = psu, strata = strata)
}

survey_model_config <- function(
    engine = c("survey", "mixed"),
    family = stats::gaussian(),
    mixed_random = NULL,
    lonely_psu = "adjust",
    export_outputs = FALSE,
    output_dir = "outputs/model_run"
) {
  engine <- match.arg(engine)
  list(
    engine = engine,
    family = family,
    mixed_random = mixed_random,
    lonely_psu = lonely_psu,
    export_outputs = export_outputs,
    output_dir = output_dir
  )
}

merge_index_scores <- function(
    data,
    index_obj,
    outcome_var = "survey_index",
    merge_keys = NULL
) {
  stopifnot(inherits(index_obj, "survey_index_result"))
  scores <- index_obj$score_data

  if (outcome_var %in% names(data)) {
    return(list(
      data = data,
      merge_performed = FALSE,
      message = sprintf("Outcome '%s' already present in data; no merge performed.", outcome_var)
    ))
  }

  if (is.null(merge_keys)) {
    merge_keys <- intersect(names(data), names(scores))
    merge_keys <- setdiff(merge_keys, c(outcome_var, "survey_index", "row_index_original"))
  }

  if (length(merge_keys) == 0) {
    if (!("row_index_original" %in% names(scores))) {
      stop("No merge keys were supplied and row_index_original is unavailable.", call. = FALSE)
    }
    data[[".__row_index_original__"]] <- seq_len(nrow(data))
    scores2 <- scores[, c("row_index_original", "survey_index"), drop = FALSE]
    names(scores2)[names(scores2) == "row_index_original"] <- ".__row_index_original__"
    merged <- merge(data, scores2, by = ".__row_index_original__", all.x = FALSE, sort = FALSE)
    merged[[".__row_index_original__"]] <- NULL
  } else {
    scores2 <- scores[, c(merge_keys, "survey_index"), drop = FALSE]
    merged <- merge(data, scores2, by = merge_keys, all.x = FALSE, sort = FALSE)
  }

  names(merged)[names(merged) == "survey_index"] <- outcome_var
  list(
    data = merged,
    merge_performed = TRUE,
    message = sprintf("Merged index scores using %s.", if (length(merge_keys) > 0) paste(merge_keys, collapse = ", ") else "row_index_original")
  )
}

coerce_model_variables <- function(data, numeric_vars = character(0), factor_vars = character(0), ordered_factors = list()) {
  messages <- data.frame(level = character(0), text = character(0), stringsAsFactors = FALSE)
  add_message <- function(level, text) {
    messages <<- rbind(messages, data.frame(level = level, text = text, stringsAsFactors = FALSE))
  }

  for (v in intersect(numeric_vars, names(data))) {
    before <- sum(is.na(data[[v]]))
    data[[v]] <- suppressWarnings(as.numeric(data[[v]]))
    after <- sum(is.na(data[[v]]))
    if (after > before) add_message("warning", sprintf("Numeric coercion introduced %d NA value(s) in %s.", after - before, v))
  }

  for (v in intersect(factor_vars, names(data))) {
    data[[v]] <- as.factor(data[[v]])
  }

  for (v in intersect(names(ordered_factors), names(data))) {
    spec <- ordered_factors[[v]]
    data[[v]] <- ordered(data[[v]], levels = spec$levels, labels = spec$labels %||% spec$levels)
  }

  list(data = data, messages = messages)
}

screen_model_data <- function(data, outcome_var, predictors, ids = NULL) {
  needed <- unique(c(outcome_var, predictors, ids$weight, ids$psu, ids$strata))
  needed <- needed[!is.null(needed) & needed %in% names(data)]
  complete <- stats::complete.cases(data[, needed, drop = FALSE])
  list(
    data = data[complete, , drop = FALSE],
    variables_used = needed,
    n_rows_before = nrow(data),
    n_rows_after = sum(complete),
    n_rows_removed = nrow(data) - sum(complete)
  )
}

fit_survey_engine <- function(data, formula, ids, config) {
  require_package("survey")
  old_opt <- getOption("survey.lonely.psu")
  on.exit(options(survey.lonely.psu = old_opt), add = TRUE)
  options(survey.lonely.psu = config$lonely_psu)

  if (is.null(ids$weight) || !(ids$weight %in% names(data))) {
    stop("A valid survey weight variable is required for engine = 'survey'.", call. = FALSE)
  }

  psu_formula <- if (!is.null(ids$psu) && ids$psu %in% names(data)) stats::as.formula(paste0("~", ids$psu)) else ~1
  strata_formula <- if (!is.null(ids$strata) && ids$strata %in% names(data)) stats::as.formula(paste0("~", ids$strata)) else NULL
  weight_formula <- stats::as.formula(paste0("~", ids$weight))

  design <- survey::svydesign(
    ids = psu_formula,
    strata = strata_formula,
    weights = weight_formula,
    data = data,
    nest = TRUE
  )

  fit <- survey::svyglm(formula, design = design, family = config$family)
  list(engine = "survey", design = design, fit = fit)
}

fit_mixed_engine <- function(data, formula, config) {
  require_package("lme4")
  if (is.null(config$mixed_random) || !nzchar(config$mixed_random)) {
    stop("mixed_random must be supplied for engine = 'mixed', e.g. '(1 | cluster_id)'.", call. = FALSE)
  }

  full_formula <- stats::as.formula(paste(deparse(formula), "+", config$mixed_random))
  fit <- lme4::lmer(full_formula, data = data, REML = FALSE)
  list(engine = "mixed", fit = fit, formula = full_formula)
}

coefficient_table <- function(fit_obj) {
  fit <- fit_obj$fit
  tab <- as.data.frame(summary(fit)$coefficients)
  tab$term <- rownames(tab)
  rownames(tab) <- NULL
  tab[, c("term", setdiff(names(tab), "term")), drop = FALSE]
}

fit_survey_index_model <- function(
    data,
    index_obj = NULL,
    outcome_var = "survey_index",
    predictors,
    ids = survey_design_ids(weight = NULL),
    merge_keys = NULL,
    numeric_vars = character(0),
    factor_vars = character(0),
    ordered_factors = list(),
    config = survey_model_config()
) {
  if (!is.data.frame(data)) stop("data must be a data.frame.", call. = FALSE)
  if (missing(predictors) || length(predictors) == 0) stop("At least one predictor is required.", call. = FALSE)

  merge_info <- NULL
  if (!(outcome_var %in% names(data))) {
    if (is.null(index_obj)) stop("Outcome is absent from data and no index_obj was supplied.", call. = FALSE)
    merge_info <- merge_index_scores(data, index_obj, outcome_var, merge_keys)
    data <- merge_info$data
  }

  missing_predictors <- setdiff(predictors, names(data))
  if (length(missing_predictors) > 0) {
    stop(sprintf("Missing predictor(s): %s", paste(missing_predictors, collapse = ", ")), call. = FALSE)
  }

  typed <- coerce_model_variables(
    data,
    numeric_vars = unique(c(outcome_var, numeric_vars, ids$weight)),
    factor_vars = unique(c(factor_vars, ids$psu, ids$strata)),
    ordered_factors = ordered_factors
  )

  screened <- screen_model_data(typed$data, outcome_var, predictors, ids)
  model_data <- screened$data

  formula <- stats::as.formula(paste(outcome_var, "~", paste(predictors, collapse = " + ")))

  fit_obj <- if (identical(config$engine, "survey")) {
    fit_survey_engine(model_data, formula, ids, config)
  } else {
    fit_mixed_engine(model_data, formula, config)
  }

  coef_tab <- coefficient_table(fit_obj)

  result <- list(
    status = "ok",
    engine = config$engine,
    formula = formula,
    fit = fit_obj$fit,
    design = fit_obj$design %||% NULL,
    coefficient_table = coef_tab,
    screening = screened,
    merge = merge_info,
    typing_messages = typed$messages,
    config_used = config
  )

  if (isTRUE(config$export_outputs)) {
    dir.create(config$output_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(coef_tab, file.path(config$output_dir, "coefficients.csv"), row.names = FALSE)
    utils::write.csv(
      data.frame(
        metric = c("n_rows_before", "n_rows_after", "n_rows_removed"),
        value = c(screened$n_rows_before, screened$n_rows_after, screened$n_rows_removed)
      ),
      file.path(config$output_dir, "sample_flow.csv"),
      row.names = FALSE
    )
    if (nrow(typed$messages) > 0) {
      utils::write.csv(typed$messages, file.path(config$output_dir, "typing_messages.csv"), row.names = FALSE)
    }
  }

  class(result) <- c("survey_index_model", class(result))
  result
}

print.survey_index_model <- function(x, ...) {
  cat("\n=== Survey index model ===\n")
  cat("Status: ", x$status, "\n", sep = "")
  cat("Engine: ", x$engine, "\n", sep = "")
  cat("Rows used: ", x$screening$n_rows_after, "/", x$screening$n_rows_before, "\n", sep = "")
  print(utils::head(x$coefficient_table, 10))
  invisible(x)
}
