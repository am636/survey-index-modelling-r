# ============================================================
# COMPONENT 2: Survey index construction
# ============================================================

if (!exists("require_package")) {
  require_package <- function(pkg) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required but not installed.", pkg), call. = FALSE)
    }
  }
}

survey_index_config <- function(
    item_source = "usable",
    override_items = NULL,
    yes_values = c(1),
    no_values = c(0),
    missing_values = c(7, 8, 9, 97, 98, 99, 997, 998, 999),
    strict = FALSE,
    require_both_01 = TRUE,
    min_items_required = 3,
    row_rule = "complete_case",
    method = c("pca", "tetrachoric"),
    orient_higher = "higher_item_mean",
    include_row_audit = TRUE
) {
  method <- match.arg(method)
  list(
    item_source = item_source,
    override_items = override_items,
    yes_values = yes_values,
    no_values = no_values,
    missing_values = missing_values,
    strict = strict,
    require_both_01 = require_both_01,
    min_items_required = min_items_required,
    row_rule = row_rule,
    method = method,
    orient_higher = orient_higher,
    include_row_audit = include_row_audit
  )
}

select_survey_items <- function(validation_obj, config) {
  if (!is.null(config$override_items)) return(unique(as.character(config$override_items)))

  if (identical(config$item_source, "usable")) {
    return(validation_obj$item_check$usable_items)
  }
  if (identical(config$item_source, "candidate")) {
    return(validation_obj$item_check$candidate_items)
  }

  stop("item_source must be 'usable' or 'candidate'.", call. = FALSE)
}

recode_binary_item <- function(x, variable, config) {
  x_num <- suppressWarnings(as.numeric(x))
  recoded <- rep(NA_real_, length(x_num))

  yes <- !is.na(x_num) & x_num %in% config$yes_values
  no <- !is.na(x_num) & x_num %in% config$no_values
  missing <- !is.na(x_num) & x_num %in% config$missing_values
  known <- yes | no | missing
  unexpected <- !is.na(x_num) & !known

  recoded[yes] <- 1
  recoded[no] <- 0

  unexpected_values <- sort(unique(x_num[unexpected]))
  if (isTRUE(config$strict) && length(unexpected_values) > 0) {
    stop(
      sprintf("Unexpected value(s) in %s: %s", variable, paste(unexpected_values, collapse = ", ")),
      call. = FALSE
    )
  }

  non_missing <- recoded[!is.na(recoded)]
  has_0 <- any(non_missing == 0)
  has_1 <- any(non_missing == 1)
  retained <- if (isTRUE(config$require_both_01)) has_0 && has_1 else has_0 || has_1

  audit <- data.frame(
    variable = variable,
    n_total = length(x_num),
    n_yes = sum(recoded == 1, na.rm = TRUE),
    n_no = sum(recoded == 0, na.rm = TRUE),
    n_missing_after_recode = sum(is.na(recoded)),
    prop_yes_among_non_missing = if (length(non_missing) > 0) mean(non_missing == 1) else NA_real_,
    has_0 = has_0,
    has_1 = has_1,
    retained = retained,
    n_unexpected_to_na = sum(unexpected),
    unexpected_values = if (length(unexpected_values) > 0) paste(unexpected_values, collapse = ", ") else NA_character_,
    stringsAsFactors = FALSE
  )

  list(recoded = recoded, audit = audit)
}

item_quality_table <- function(item_df) {
  if (ncol(item_df) == 0) return(data.frame())
  do.call(rbind, lapply(names(item_df), function(v) {
    x <- item_df[[v]]
    non_missing <- x[!is.na(x)]
    data.frame(
      variable = v,
      n_non_missing = sum(!is.na(x)),
      n_missing = sum(is.na(x)),
      prop_missing = mean(is.na(x)),
      n_zero = sum(x == 0, na.rm = TRUE),
      n_one = sum(x == 1, na.rm = TRUE),
      prop_one = if (length(non_missing) > 0) mean(non_missing == 1) else NA_real_,
      variance = if (length(non_missing) > 1) stats::var(non_missing) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

row_audit_table <- function(item_df) {
  data.frame(
    row_index = seq_len(nrow(item_df)),
    n_items_total = ncol(item_df),
    n_non_missing_items = rowSums(!is.na(item_df)),
    n_missing_items = rowSums(is.na(item_df)),
    complete_case = stats::complete.cases(item_df),
    stringsAsFactors = FALSE
  )
}

estimate_index_pca <- function(item_matrix, orient_higher = "higher_item_mean") {
  fit <- stats::prcomp(item_matrix, center = TRUE, scale. = TRUE)
  score <- as.numeric(fit$x[, 1])
  loadings <- fit$rotation[, 1]

  item_mean <- rowMeans(item_matrix)
  correlation_with_item_mean <- suppressWarnings(stats::cor(score, item_mean))
  reversed <- FALSE

  if (identical(orient_higher, "higher_item_mean") && !is.na(correlation_with_item_mean) && correlation_with_item_mean < 0) {
    score <- -score
    loadings <- -loadings
    correlation_with_item_mean <- -correlation_with_item_mean
    reversed <- TRUE
  }

  list(
    method = "pca",
    fit = fit,
    scores = score,
    loadings = data.frame(variable = names(loadings), loading = as.numeric(loadings), stringsAsFactors = FALSE),
    variance = data.frame(
      component = paste0("PC", seq_along(fit$sdev)),
      eigenvalue = fit$sdev^2,
      proportion = fit$sdev^2 / sum(fit$sdev^2),
      stringsAsFactors = FALSE
    ),
    orientation = list(
      orient_higher = orient_higher,
      correlation_with_item_mean = correlation_with_item_mean,
      reversed = reversed
    )
  )
}

estimate_index_tetrachoric <- function(item_matrix, orient_higher = "higher_item_mean") {
  require_package("psych")

  tc <- psych::tetrachoric(item_matrix)$rho
  fit <- psych::fa(tc, nfactors = 1, fm = "minres", rotate = "none")
  loadings <- as.numeric(fit$loadings[, 1])
  names(loadings) <- colnames(item_matrix)

  raw_score <- as.numeric(scale(item_matrix) %*% loadings)
  item_mean <- rowMeans(item_matrix)
  correlation_with_item_mean <- suppressWarnings(stats::cor(raw_score, item_mean))
  reversed <- FALSE

  if (identical(orient_higher, "higher_item_mean") && !is.na(correlation_with_item_mean) && correlation_with_item_mean < 0) {
    raw_score <- -raw_score
    loadings <- -loadings
    correlation_with_item_mean <- -correlation_with_item_mean
    reversed <- TRUE
  }

  list(
    method = "tetrachoric",
    fit = fit,
    scores = raw_score,
    loadings = data.frame(variable = names(loadings), loading = as.numeric(loadings), stringsAsFactors = FALSE),
    variance = data.frame(),
    orientation = list(
      orient_higher = orient_higher,
      correlation_with_item_mean = correlation_with_item_mean,
      reversed = reversed
    )
  )
}

construct_survey_index <- function(validation_obj, config = survey_index_config()) {
  stopifnot(inherits(validation_obj, "survey_validation_result"))
  if (is.null(validation_obj$data)) {
    stop("validation_obj$data is NULL. Re-run validation with keep_data = TRUE.", call. = FALSE)
  }

  data <- validation_obj$data
  selected_items <- select_survey_items(validation_obj, config)
  selected_items <- selected_items[selected_items %in% names(data)]

  if (length(selected_items) == 0) stop("No selected items were found in the data.", call. = FALSE)

  recoded <- vector("list", length(selected_items))
  names(recoded) <- selected_items
  audits <- vector("list", length(selected_items))

  for (i in seq_along(selected_items)) {
    res <- recode_binary_item(data[[selected_items[i]]], selected_items[i], config)
    recoded[[i]] <- res$recoded
    audits[[i]] <- res$audit
  }

  recoded_all <- as.data.frame(recoded, stringsAsFactors = FALSE)
  item_audit <- do.call(rbind, audits)
  retained_items <- item_audit$variable[item_audit$retained]
  dropped_items <- setdiff(selected_items, retained_items)

  if (length(retained_items) < config$min_items_required) {
    stop(
      sprintf("Only %d item(s) retained; minimum required is %d.", length(retained_items), config$min_items_required),
      call. = FALSE
    )
  }

  recoded_retained <- recoded_all[, retained_items, drop = FALSE]
  row_audit <- if (isTRUE(config$include_row_audit)) row_audit_table(recoded_retained) else NULL

  if (!identical(config$row_rule, "complete_case")) {
    stop("Only row_rule = 'complete_case' is implemented.", call. = FALSE)
  }

  complete_case_index <- stats::complete.cases(recoded_retained)
  item_matrix <- as.matrix(recoded_retained[complete_case_index, , drop = FALSE])
  storage.mode(item_matrix) <- "numeric"

  if (nrow(item_matrix) == 0) stop("No complete-case rows remain for index construction.", call. = FALSE)

  index_fit <- if (identical(config$method, "pca")) {
    estimate_index_pca(item_matrix, config$orient_higher)
  } else {
    estimate_index_tetrachoric(item_matrix, config$orient_higher)
  }

  id_vars <- intersect(validation_obj$schema_check$required_present, names(data))
  id_data_complete <- if (length(id_vars) > 0) data[complete_case_index, id_vars, drop = FALSE] else {
    data.frame(row_index = which(complete_case_index))
  }

  score_data <- cbind(
    id_data_complete,
    data.frame(
      row_index_original = which(complete_case_index),
      survey_index = as.numeric(scale(index_fit$scores)),
      stringsAsFactors = FALSE
    )
  )

  result <- list(
    status = "ok",
    config_used = config,
    selected_items = selected_items,
    retained_items = retained_items,
    dropped_items = dropped_items,
    item_audit = item_audit,
    item_quality = item_quality_table(recoded_retained),
    row_audit = row_audit,
    complete_case_index = complete_case_index,
    item_matrix = item_matrix,
    index_fit = index_fit,
    score_data = score_data,
    summary = list(
      n_selected_items = length(selected_items),
      n_retained_items = length(retained_items),
      n_complete_case_rows = nrow(item_matrix),
      n_total_rows = nrow(data),
      method = config$method
    )
  )

  class(result) <- c("survey_index_result", class(result))
  result
}

print.survey_index_result <- function(x, ...) {
  cat("\n=== Survey index construction ===\n")
  cat("Status: ", x$status, "\n", sep = "")
  cat("Method: ", x$summary$method, "\n", sep = "")
  cat("Selected items: ", x$summary$n_selected_items, "\n", sep = "")
  cat("Retained items: ", x$summary$n_retained_items, "\n", sep = "")
  cat("Complete-case rows: ", x$summary$n_complete_case_rows, "/", x$summary$n_total_rows, "\n", sep = "")
  invisible(x)
}

survey_index_summary_table <- function(index_obj) {
  stopifnot(inherits(index_obj, "survey_index_result"))
  data.frame(
    metric = c("selected_items", "retained_items", "complete_case_rows", "total_rows", "method"),
    value = c(
      index_obj$summary$n_selected_items,
      index_obj$summary$n_retained_items,
      index_obj$summary$n_complete_case_rows,
      index_obj$summary$n_total_rows,
      index_obj$summary$method
    ),
    stringsAsFactors = FALSE
  )
}