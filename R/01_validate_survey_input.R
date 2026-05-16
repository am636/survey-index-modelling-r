# ============================================================
# COMPONENT 1: Survey input validation
# ============================================================

require_package <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf("Package '%s' is required but not installed.", pkg), call. = FALSE)
  }
}

`%||%` <- function(x, y) if (is.null(x)) y else x

survey_validation_config <- function(
    required_ids = c("cluster_id", "household_id", "respondent_id", "weight"),
    optional_vars = c("psu", "strata", "region", "urban_rural"),
    candidate_items = character(0),
    candidate_name_regex = NULL,
    candidate_label_regex = NULL,
    standardise_names_to_lower = TRUE,
    keep_data = TRUE,
    include_full_schema_table = FALSE
) {
  list(
    required_ids = required_ids,
    optional_vars = optional_vars,
    candidate_items = candidate_items,
    candidate_name_regex = candidate_name_regex,
    candidate_label_regex = candidate_label_regex,
    standardise_names_to_lower = standardise_names_to_lower,
    keep_data = keep_data,
    include_full_schema_table = include_full_schema_table
  )
}

var_label <- function(x) {
  lbl <- attr(x, "label", exact = TRUE)
  if (is.null(lbl) || length(lbl) == 0 || is.na(lbl[1])) return(NA_character_)
  as.character(lbl)[1]
}

numeric_values <- function(x) {
  out <- suppressWarnings(as.numeric(x))
  out[!is.na(out)]
}

is_binary_like <- function(x, allowed_special = c(7, 8, 9, 97, 98, 99, 997, 998, 999)) {
  vals <- sort(unique(numeric_values(x)))
  if (length(vals) == 0) return(FALSE)
  all(vals %in% c(0, 1, allowed_special))
}

has_both_binary_values <- function(x) {
  vals <- sort(unique(numeric_values(x)))
  all(c(0, 1) %in% vals)
}

audit_variable <- function(data, variable) {
  x <- data[[variable]]
  vals <- numeric_values(x)
  unique_vals <- sort(unique(vals))
  shown_vals <- if (length(unique_vals) == 0) {
    NA_character_
  } else {
    txt <- paste(utils::head(unique_vals, 10), collapse = ", ")
    if (length(unique_vals) > 10) txt <- paste0(txt, ", ...")
    txt
  }

  data.frame(
    variable = variable,
    label = var_label(x),
    class = paste(class(x), collapse = ", "),
    n_total = length(x),
    n_missing = sum(is.na(x)),
    n_non_missing = sum(!is.na(x)),
    n_unique_numeric = length(unique_vals),
    binary_like = is_binary_like(x),
    has_0_and_1 = has_both_binary_values(x),
    min_value = if (length(vals) > 0) min(vals) else NA_real_,
    max_value = if (length(vals) > 0) max(vals) else NA_real_,
    observed_values_preview = shown_vals,
    stringsAsFactors = FALSE
  )
}

schema_table <- function(data) {
  data.frame(
    variable = names(data),
    class = vapply(data, function(x) paste(class(x), collapse = ", "), character(1)),
    label = vapply(data, var_label, character(1)),
    n_missing = vapply(data, function(x) sum(is.na(x)), integer(1)),
    n_unique_numeric = vapply(data, function(x) length(unique(numeric_values(x))), integer(1)),
    stringsAsFactors = FALSE
  )
}

detect_candidate_items <- function(data, config) {
  nms <- names(data)
  configured <- intersect(config$candidate_items %||% character(0), nms)

  regex_hits <- character(0)
  if (!is.null(config$candidate_name_regex) && nzchar(config$candidate_name_regex)) {
    regex_hits <- union(regex_hits, nms[grepl(config$candidate_name_regex, nms, ignore.case = TRUE)])
  }

  if (!is.null(config$candidate_label_regex) && nzchar(config$candidate_label_regex)) {
    labels <- vapply(data, var_label, character(1))
    labels[is.na(labels)] <- ""
    regex_hits <- union(regex_hits, nms[grepl(config$candidate_label_regex, labels, ignore.case = TRUE)])
  }

  unique(c(configured, regex_hits))
}

validate_survey_input <- function(file_path, config = survey_validation_config()) {
  require_package("haven")

  if (!is.character(file_path) || length(file_path) != 1 || !nzchar(file_path)) {
    stop("file_path must be a single non-empty character string.", call. = FALSE)
  }
  if (!file.exists(file_path)) {
    stop(sprintf("File not found: %s", file_path), call. = FALSE)
  }

  data <- tryCatch(
    haven::read_dta(file_path),
    error = function(e) stop(sprintf("Could not read file: %s", conditionMessage(e)), call. = FALSE)
  )

  original_names <- names(data)
  if (isTRUE(config$standardise_names_to_lower)) names(data) <- tolower(names(data))

  required_present <- intersect(config$required_ids, names(data))
  required_missing <- setdiff(config$required_ids, names(data))
  optional_present <- intersect(config$optional_vars, names(data))
  optional_missing <- setdiff(config$optional_vars, names(data))

  required_audit <- if (length(required_present) > 0) {
    do.call(rbind, lapply(required_present, function(v) audit_variable(data, v)))
  } else data.frame()

  optional_audit <- if (length(optional_present) > 0) {
    do.call(rbind, lapply(optional_present, function(v) audit_variable(data, v)))
  } else data.frame()

  candidates <- detect_candidate_items(data, config)
  candidate_audit <- if (length(candidates) > 0) {
    do.call(rbind, lapply(candidates, function(v) audit_variable(data, v)))
  } else data.frame()

  usable_items <- if (nrow(candidate_audit) > 0) {
    candidate_audit$variable[candidate_audit$binary_like & candidate_audit$has_0_and_1]
  } else character(0)

  info <- file.info(file_path)
  messages <- data.frame(
    level = character(0),
    text = character(0),
    stringsAsFactors = FALSE
  )

  add_message <- function(level, text) {
    messages <<- rbind(messages, data.frame(level = level, text = text, stringsAsFactors = FALSE))
  }

  if (length(required_missing) > 0) {
    add_message("error", paste("Missing required variable(s):", paste(required_missing, collapse = ", ")))
  }
  if (length(usable_items) == 0) {
    add_message("warning", "No candidate binary items were provisionally usable.")
  }

  result <- list(
    status = if (any(messages$level == "error")) "error" else "ok",
    metadata = list(
      file_name = basename(file_path),
      file_size_bytes = unname(info$size),
      n_rows = nrow(data),
      n_cols = ncol(data),
      names_standardised_to_lower = isTRUE(config$standardise_names_to_lower)
    ),
    name_lookup = data.frame(
      original_name = original_names,
      standardised_name = names(data),
      stringsAsFactors = FALSE
    ),
    schema_check = list(
      required_present = required_present,
      required_missing = required_missing,
      optional_present = optional_present,
      optional_missing = optional_missing,
      required_audit = required_audit,
      optional_audit = optional_audit,
      required_ok = length(required_missing) == 0
    ),
    item_check = list(
      candidate_items = candidates,
      candidate_audit = candidate_audit,
      usable_items = usable_items
    ),
    full_schema_table = if (isTRUE(config$include_full_schema_table)) schema_table(data) else NULL,
    messages = messages,
    data = if (isTRUE(config$keep_data)) data else NULL,
    config_used = config
  )

  class(result) <- c("survey_validation_result", class(result))
  result
}

print.survey_validation_result <- function(x, ...) {
  cat("\n=== Survey input validation ===\n")
  cat("Status: ", x$status, "\n", sep = "")
  cat("File:   ", x$metadata$file_name, "\n", sep = "")
  cat("Rows:   ", x$metadata$n_rows, "\n", sep = "")
  cat("Cols:   ", x$metadata$n_cols, "\n", sep = "")
  cat("\nRequired variables present: ", length(x$schema_check$required_present), "\n", sep = "")
  if (length(x$schema_check$required_missing) > 0) {
    cat("Missing required variables: ", paste(x$schema_check$required_missing, collapse = ", "), "\n", sep = "")
  }
  cat("Candidate binary items: ", length(x$item_check$candidate_items), "\n", sep = "")
  cat("Provisionally usable items: ", length(x$item_check$usable_items), "\n", sep = "")
  invisible(x)
}

validation_summary_table <- function(validation_obj) {
  stopifnot(inherits(validation_obj, "survey_validation_result"))
  data.frame(
    metric = c(
      "rows",
      "columns",
      "required_present",
      "required_missing",
      "candidate_items",
      "usable_items"
    ),
    value = c(
      validation_obj$metadata$n_rows,
      validation_obj$metadata$n_cols,
      length(validation_obj$schema_check$required_present),
      length(validation_obj$schema_check$required_missing),
      length(validation_obj$item_check$candidate_items),
      length(validation_obj$item_check$usable_items)
    ),
    stringsAsFactors = FALSE
  )
}

# Backwards-compatible alias used by the example script.
load_and_validate_survey <- validate_survey_input
