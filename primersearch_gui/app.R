library(shiny)
library(jsonlite)

max_upload_mb <- suppressWarnings(as.integer(Sys.getenv("SHINY_MAX_UPLOAD_MB", "1024")))
if (is.na(max_upload_mb) || max_upload_mb <= 0) {
  max_upload_mb <- 1024L
}
options(shiny.maxRequestSize = max_upload_mb * 1024^2)

get_app_dir <- function() {
  app_dir <- NULL
  frame_info <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(frame_info)) {
    app_dir <- dirname(frame_info)
  }
  if (is.null(app_dir) || !nzchar(app_dir)) {
    app_dir <- getwd()
  }
  normalizePath(app_dir)
}

read_tail <- function(path, n = 200L) {
  if (!file.exists(path)) {
    return(character(0))
  }
  lines <- readLines(path, warn = FALSE)
  if (length(lines) > n) {
    lines <- tail(lines, n)
  }
  lines
}

parse_optional_int <- function(value) {
  trimmed <- trimws(value)
  if (!nzchar(trimmed)) {
    return(NULL)
  }
  parsed <- suppressWarnings(as.integer(trimmed))
  if (is.na(parsed)) {
    return(NA_integer_)
  }
  parsed
}

app_dir <- get_app_dir()
runs_dir <- file.path(app_dir, "runs")
dir.create(runs_dir, recursive = TRUE, showWarnings = FALSE)

script_path <- normalizePath(
  file.path(app_dir, "..", "run_primersearch.py"),
  mustWork = FALSE
)

ui <- fluidPage(
  titlePanel("Primersearch GUI"),
  sidebarLayout(
    sidebarPanel(
      fileInput("primers", "Primers TSV", accept = c(".tsv", ".txt")),
      fileInput("config", "Config JSON (optional)", accept = c(".json")),
      fileInput(
        "genome_file",
        "Genome file (optional)",
        accept = c(".fa", ".fasta", ".fna", ".fas", ".fsa", ".txt")
      ),
      textInput("genome", "Genome path", value = ""),
      numericInput("mismatch", "Mismatch percent", value = 0, min = 0, step = 1),
      textInput("output", "Output filename", value = "resultats.primersearch"),
      checkboxInput("auto", "Auto", value = TRUE),
      checkboxInput("verbose", "Verbose", value = FALSE),
      tags$details(
        summary = "Advanced options",
        textInput("sbegin", "sbegin (optional)", value = ""),
        textInput("send", "send (optional)", value = ""),
        checkboxInput("sreverse", "sreverse", value = FALSE),
        checkboxInput("scircular", "scircular", value = FALSE)
      ),
      actionButton("run", "Run primersearch")
    ),
    mainPanel(
      verbatimTextOutput("config_status"),
      verbatimTextOutput("run_status"),
      tags$hr(),
      h4("Stdout (tail)"),
      verbatimTextOutput("run_stdout"),
      h4("Stderr (tail)"),
      verbatimTextOutput("run_stderr"),
      h4("Output preview (tail)"),
      uiOutput("run_output"),
      downloadButton("download_output", "Download output")
    )
  )
)

server <- function(input, output, session) {
  config_info <- reactive({
    if (is.null(input$config)) {
      return(list(config = list(), error = NULL))
    }
    parsed <- tryCatch(
      fromJSON(input$config$datapath, simplifyVector = TRUE),
      error = function(e) e
    )
    if (inherits(parsed, "error")) {
      return(list(config = list(), error = conditionMessage(parsed)))
    }
    list(config = as.list(parsed), error = NULL)
  })

  observeEvent(input$config, {
    info <- config_info()
    if (!is.null(info$error)) {
      return()
    }
    cfg <- info$config
    if (!is.null(cfg$genome)) {
      updateTextInput(session, "genome", value = as.character(cfg$genome))
    }
    if (!is.null(cfg$mismatchpercent)) {
      updateNumericInput(
        session,
        "mismatch",
        value = as.integer(cfg$mismatchpercent)
      )
    }
    if (!is.null(cfg$output)) {
      updateTextInput(session, "output", value = as.character(cfg$output))
    }
    if (!is.null(cfg$auto)) {
      updateCheckboxInput(session, "auto", value = isTRUE(cfg$auto))
    }
    if (!is.null(cfg$verbose)) {
      updateCheckboxInput(session, "verbose", value = isTRUE(cfg$verbose))
    }
    if (!is.null(cfg$sbegin)) {
      updateTextInput(session, "sbegin", value = as.character(cfg$sbegin))
    }
    if (!is.null(cfg$send)) {
      updateTextInput(session, "send", value = as.character(cfg$send))
    }
    if (!is.null(cfg$sreverse)) {
      updateCheckboxInput(session, "sreverse", value = isTRUE(cfg$sreverse))
    }
    if (!is.null(cfg$scircular)) {
      updateCheckboxInput(session, "scircular", value = isTRUE(cfg$scircular))
    }
  })

  run_result <- reactiveVal(NULL)

  observeEvent(input$run, {
    withProgress(message = "Running primersearch", value = 0, {
      incProgress(0.1, detail = "Loading configuration")
      info <- config_info()
      if (!is.null(info$error)) {
        run_result(list(status = "error", message = info$error))
        return()
      }
      cfg <- info$config

      incProgress(0.15, detail = "Validating inputs")
      primer_source <- NULL
      if (!is.null(input$primers)) {
        primer_source <- input$primers$datapath
      } else if (!is.null(cfg$primer_table) && file.exists(cfg$primer_table)) {
        primer_source <- cfg$primer_table
      }
      if (is.null(primer_source)) {
        run_result(list(
          status = "error",
          message = "Provide primers TSV or a valid primer_table in the config."
        ))
        return()
      }

      genome_upload <- NULL
      if (!is.null(input$genome_file)) {
        genome_upload <- list(
          path = input$genome_file$datapath,
          name = input$genome_file$name
        )
      }

      genome_path <- NULL
      if (is.null(genome_upload)) {
        genome <- trimws(input$genome)
        if (nzchar(genome)) {
          cfg$genome <- genome
        }
        if (!is.null(cfg$genome) && nzchar(cfg$genome)) {
          genome_path <- cfg$genome
        }
      }
      if (is.null(genome_upload) && is.null(genome_path)) {
        run_result(list(
          status = "error",
          message = "Provide a genome file or a genome path."
        ))
        return()
      }
      if (!is.null(genome_path) && !file.exists(genome_path)) {
        run_result(list(
          status = "error",
          message = paste("Genome path not found:", genome_path)
        ))
        return()
      }

      mismatch_val <- as.integer(input$mismatch)
      if (is.na(mismatch_val) || mismatch_val < 0) {
        run_result(list(
          status = "error",
          message = "Mismatch percent must be a non-negative integer."
        ))
        return()
      }

      output_name <- trimws(input$output)
      if (!nzchar(output_name)) {
        output_name <- "resultats.primersearch"
      }

      sbegin_val <- parse_optional_int(input$sbegin)
      if (!is.null(sbegin_val) && is.na(sbegin_val)) {
        run_result(list(status = "error", message = "sbegin must be an integer."))
        return()
      }
      send_val <- parse_optional_int(input$send)
      if (!is.null(send_val) && is.na(send_val)) {
        run_result(list(status = "error", message = "send must be an integer."))
        return()
      }

      incProgress(0.2, detail = "Preparing run directory")
      timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
      run_dir <- file.path(runs_dir, paste0("run_", timestamp))
      dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)

      primer_copy <- file.path(run_dir, "primers.tsv")
      copy_ok <- file.copy(primer_source, primer_copy, overwrite = TRUE)
      if (!copy_ok) {
        run_result(list(
          status = "error",
          message = "Failed to copy primers TSV into the run directory."
        ))
        return()
      }

      cfg$primer_table <- primer_copy
      if (!is.null(genome_upload)) {
        incProgress(0.05, detail = "Copying genome file")
        genome_name <- basename(genome_upload$name)
        if (!nzchar(genome_name)) {
          genome_name <- "genome.fasta"
        }
        genome_copy <- file.path(run_dir, genome_name)
        genome_ok <- file.copy(genome_upload$path, genome_copy, overwrite = TRUE)
        if (!genome_ok) {
          run_result(list(
            status = "error",
            message = "Failed to copy genome file into the run directory."
          ))
          return()
        }
        cfg$genome <- genome_copy
      } else {
        cfg$genome <- genome_path
      }
      cfg$mismatchpercent <- mismatch_val
      cfg$output <- output_name
      cfg$auto <- isTRUE(input$auto)
      cfg$verbose <- isTRUE(input$verbose)
      cfg$sreverse <- isTRUE(input$sreverse)
      cfg$scircular <- isTRUE(input$scircular)
      if (!is.null(sbegin_val)) {
        cfg$sbegin <- sbegin_val
      } else {
        cfg$sbegin <- NULL
      }
      if (!is.null(send_val)) {
        cfg$send <- send_val
      } else {
        cfg$send <- NULL
      }

      incProgress(0.15, detail = "Writing config")
      config_path <- file.path(run_dir, "primersearch_config.json")
      write_json(cfg, config_path, auto_unbox = TRUE, pretty = TRUE, null = "null")

      stdout_path <- file.path(run_dir, "primersearch_stdout.txt")
      stderr_path <- file.path(run_dir, "primersearch_stderr.txt")

      incProgress(0.1, detail = "Building command")
      python_bin <- Sys.which("python3")
      if (!nzchar(python_bin)) {
        python_bin <- "python3"
      }
      if (!file.exists(script_path)) {
        run_result(list(
          status = "error",
          message = paste("Script not found:", script_path)
        ))
        return()
      }

      cmd_parts <- c(
        shQuote(python_bin),
        shQuote(script_path),
        "--config",
        shQuote(config_path),
        "--workdir",
        shQuote(run_dir)
      )
      cmd <- paste(cmd_parts, collapse = " ")
      cmd <- paste(cmd, ">", shQuote(stdout_path), "2>", shQuote(stderr_path))

      incProgress(0.25, detail = "Running primersearch (this may take a while)")
      exit_status <- tryCatch(
        system(cmd, intern = FALSE, ignore.stdout = TRUE, ignore.stderr = TRUE),
        error = function(e) e
      )

      if (inherits(exit_status, "error")) {
        run_result(list(
          status = "error",
          message = conditionMessage(exit_status)
        ))
        return()
      }

      incProgress(0.05, detail = "Finalizing")
      output_path <- file.path(run_dir, output_name)
      run_result(list(
        status = "done",
        run_dir = run_dir,
        exit_status = exit_status,
        command = cmd,
        stdout_path = stdout_path,
        stderr_path = stderr_path,
        output_path = output_path,
        output_exists = file.exists(output_path)
      ))
    })
  })

  output$config_status <- renderText({
    info <- config_info()
    if (!is.null(info$error)) {
      return(paste("Config error:", info$error))
    }
    if (is.null(input$config)) {
      return("Config: none loaded")
    }
    "Config loaded"
  })

  output$run_status <- renderText({
    result <- run_result()
    if (is.null(result)) {
      return("No run yet.")
    }
    if (identical(result$status, "error")) {
      return(paste("Error:", result$message))
    }
    status_lines <- c(
      paste("Run dir:", result$run_dir),
      paste("Exit status:", result$exit_status),
      paste("Output file exists:", result$output_exists),
      paste("Script path:", script_path)
    )
    if (!is.null(result$command)) {
      status_lines <- c(status_lines, paste("Command:", result$command))
    }
    paste(status_lines, collapse = "\n")
  })

  output$run_stdout <- renderText({
    result <- run_result()
    if (is.null(result) || is.null(result$stdout_path)) {
      return("")
    }
    paste(read_tail(result$stdout_path), collapse = "\n")
  })

  output$run_stderr <- renderText({
    result <- run_result()
    if (is.null(result) || is.null(result$stderr_path)) {
      return("")
    }
    paste(read_tail(result$stderr_path), collapse = "\n")
  })

  output$run_output <- renderUI({
    result <- run_result()
    if (is.null(result) || !isTRUE(result$output_exists)) {
      return("")
    }
    lines <- read_tail(result$output_path)
    highlighted <- vapply(lines, function(line) {
      if (grepl("^\\s*Amplimer length:", line)) {
        sprintf(
          "<span style=\"color:#c00; font-weight:600;\">%s</span>",
          htmltools::htmlEscape(line)
        )
      } else {
        htmltools::htmlEscape(line)
      }
    }, character(1))
    htmltools::tags$pre(htmltools::HTML(paste(highlighted, collapse = "\n")))
  })

  output$download_output <- downloadHandler(
    filename = function() {
      result <- run_result()
      if (is.null(result) || !isTRUE(result$output_exists)) {
        return("primersearch_output.txt")
      }
      basename(result$output_path)
    },
    content = function(file) {
      result <- run_result()
      if (is.null(result) || !isTRUE(result$output_exists)) {
        writeLines("Output file not available.", file)
        return()
      }
      file.copy(result$output_path, file)
    }
  )
}

shinyApp(ui = ui, server = server)
