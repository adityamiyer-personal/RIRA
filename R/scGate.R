#' @include Utils.R

utils::globalVariables(
  names = c('scGateConsensus'),
  package = 'RIRA',
  add = TRUE
)

#' @import scGate
#'
#' @title Run scGate
#'
#' @description Helper function to run scGate
#' @param seuratObj The seurat object
#' @param model Either an scGate model, or a character that will be passed to GetScGateModel()
#' @param min.cells Passed directly to scGate::scGate. Stop iterating if fewer than this number of cells is left
#' @param assay Passed directly to scGate::scGate. Seurat assay to use
#' @param pos.thr Passed directly to scGate::scGate. Minimum UCell score value for positive signatures
#' @param neg.thr Passed directly to scGate::scGate. Maximum UCell score value for negative signatures
#' @param ncores Passed directly to scGate::scGate. Number of processors for parallel processing (requires future.apply)
#' @param output.col.name Passed directly to scGate::scGate. Column name with 'pure/impure' annotation
#' @param genes.blacklist Passed directly to scGate::scGate. Genes blacklisted from variable features. The default loads the list of genes in scGate::genes.blacklist.default; you may deactivate blacklisting by setting genes.blacklist=NULL
#' @param doPlotUCellScores If true, FeaturePlots will be created for each UCell score used in classification
#' @param keep.ranks Passed directly to keep.ranks
#'
#' @export
RunScGate <- function(seuratObj, model, min.cells = 30, assay = 'RNA', pos.thr = 0.2, neg.thr = 0.2, ncores = 1, output.col.name = "is.pure", genes.blacklist = 'default', doPlotUCellScores = TRUE, keep.ranks = FALSE) {
  if (is.character(model)) {
    model <- GetScGateModel(model)
    if (is.null(model)) {
      stop(paste0('Unknown gate model: ', model))
    }
  }

  seuratObj <- suppressWarnings(scGate::scGate(data = seuratObj,
                        model = model,
                        min.cells = min.cells,
                        assay = assay,
                        pos.thr = pos.thr,
                        neg.thr = neg.thr,
                        seed = GetSeed(),
                        ncores = ncores,
                        keep.ranks = keep.ranks,
                        progressbar = FALSE,
                        output.col.name = output.col.name,
                        genes.blacklist = genes.blacklist
  ))

  if (length(names(seuratObj@reductions)) > 0) {
    print(Seurat::DimPlot(seuratObj, group.by = output.col.name))
    colNames <- names(seuratObj@meta.data)[grepl(names(seuratObj@meta.data), pattern = paste0('^', output.col.name, '.'))]
    for (col in colNames) {
      print(Seurat::DimPlot(seuratObj, group.by = col))
    }
  } else {
    print('There are no reductions in this seurat object, cannot create dimplots')
  }

  if (doPlotUCellScores) {
    .PlotUCellScores(seuratObj)
  }

  return(seuratObj)
}

.PlotUCellScores <- function(seuratObj) {
  if (length(names(seuratObj@reductions)) > 0) {
    colNames <- names(seuratObj@meta.data)[grepl(names(seuratObj@meta.data), pattern = paste0('UCell$'))]
    for (col in colNames) {
      tryCatch({
        suppressWarnings(print(Seurat::FeaturePlot(seuratObj, features = col, min.cutoff = 'q05', max.cutoff = 'q95')))
      }, error = function(e){
        print(paste0("Error generating UCell FeaturePlot for: ", col))
        print(conditionMessage(e))
      })
    }
  } else {
    print('There are no reductions in this seurat object, cannot create UCell FeaturePlots')
  }
}

#' @title GetAvailableScGates
#'
#' @description Return a list of available scGate models
#' @export
GetAvailableScGates <- function() {
  dir <- system.file("gates", package = "RIRA")
  files <- list.files(dir, recursive = FALSE, full.names = FALSE)
  files <- files[files != 'master_table.tsv']
  files <- sapply(files, function(x){
    return(gsub(x, pattern = '.tsv', replacement = ''))
  })

  return(files)
}

#' @title GetScGateModel
#'
#' @description Returns the selected scGate model
#' @param modelName The name of the gate to return. See GetAvailableScGates() for a list of known gates
#' @param allowSCGateDB If true, this will search local models and the models provided by scGate::get_scGateDB()
#' @importFrom magrittr %>%
#' @export
GetScGateModel <- function(modelName, allowSCGateDB = TRUE) {
  gateFile <- system.file(paste0("gates/", modelName, ".tsv"), package = "RIRA")
  if (file.exists(gateFile)) {
    masterFile <- system.file("gates/master_table.tsv", package = "RIRA")
    return(scGate::load_scGate_model(gateFile, master.table = masterFile))
  }

  if (!allowSCGateDB) {
    stop(paste0('Unable to find gate: ', modelName))
  }

  modelDir <- gsub(tempdir(), pattern = '\\\\', replacement = '/')
  models.DB <- suppressWarnings(scGate::get_scGateDB(force_update = T, destination = modelDir))
  if (!modelName %in% names(models.DB$human$generic)){
    stop(paste0('Unable to find model: ', modelName))
  }

  print(paste0('Using built-in model: ', modelName))
  return(models.DB$human$generic[[modelName]])
}

#' @title Run scGate With DefaultModels
#'
#' @description Helper function to run scGate, running all human models in scGate::get_sc()
#' @param seuratObj The seurat object
#' @param min.cells Passed directly to scGate::scGate. Stop iterating if fewer than this number of cells is left
#' @param assay Passed directly to scGate::scGate. Seurat assay to use
#' @param pos.thr Passed directly to scGate::scGate. Minimum UCell score value for positive signatures
#' @param neg.thr Passed directly to scGate::scGate. Maximum UCell score value for negative signatures
#' @param ncores Passed directly to scGate::scGate. Number of processors for parallel processing (requires future.apply)
#' @param genes.blacklist Passed directly to scGate::scGate. Genes blacklisted from variable features. The default loads the list of genes in scGate::genes.blacklist.default; you may deactivate blacklisting by setting genes.blacklist=NULL
#' @param labelRename An optional list that maps the model name to the final label that should be used in the seurat object. for exmaple: list(Tcell = 'T_NK', NK = 'T_NK'), would re-label cells classified as either 'Tcell' or 'NK' by those models to one common label of T_NK
#' @param dropAmbiguousConsensusValues If true, any consensus calls that are ambiguous will be set to NA
#' @param excludedModels An optional vector of model names to exclude
#'
#' @export
RunScGateWithDefaultModels <- function(seuratObj, min.cells = 30, assay = 'RNA', pos.thr = 0.13, neg.thr = 0.13, ncores = 1, genes.blacklist = 'default', labelRename = NULL, dropAmbiguousConsensusValues = FALSE, excludedModels = c('Male', 'Female')) {
  modelDir <- gsub(tempdir(), pattern = '\\\\', replacement = '/')
  models.DB <- suppressWarnings(scGate::get_scGateDB(force_update = T, destination = modelDir))
  modelNames <- names(models.DB$human$generic)
  if (!is.null(excludedModels)) {
    modelNames <- modelNames[!modelNames %in% excludedModels]
  }

  return(RunScGateForModels(seuratObj,
                            modelNames = modelNames,
                            min.cells = min.cells,
                            assay = assay,
                            pos.thr = pos.thr,
                            neg.thr = neg.thr,
                            ncores = ncores,
                            genes.blacklist = genes.blacklist,
                            labelRename = labelRename,
                            dropAmbiguousConsensusValues = dropAmbiguousConsensusValues
  ))
}

#' @title Run scGate using Rhesus macaque models
#'
#' @description Helper function to run scGate, iterating the provided models and generating a consensus field
#' @param seuratObj The seurat object
#' @param min.cells Passed directly to scGate::scGate. Stop iterating if fewer than this number of cells is left
#' @param assay Passed directly to scGate::scGate. Seurat assay to use
#' @param pos.thr Passed directly to scGate::scGate. Minimum UCell score value for positive signatures
#' @param neg.thr Passed directly to scGate::scGate. Maximum UCell score value for negative signatures
#' @param ncores Passed directly to scGate::scGate. Number of processors for parallel processing (requires future.apply)
#' @param genes.blacklist Passed directly to scGate::scGate. Genes blacklisted from variable features. The default loads the list of genes in scGate::genes.blacklist.default; you may deactivate blacklisting by setting genes.blacklist=NULL
#' @param dropAmbiguousConsensusValues If true, any consensus calls that are ambiguous will be set to NA
#'
#' @export
RunScGateWithRhesusModels <- function(seuratObj, min.cells = 30, assay = 'RNA', pos.thr = 0.13, neg.thr = 0.13, ncores = 1, genes.blacklist = 'default', dropAmbiguousConsensusValues = FALSE) {
  mn <- c('Bcell.RM', 'Tcell.RM', 'NK.RM', 'Myeloid.RM', 'AvEp.RM', 'Epithelial.RM', 'Erythrocyte.RM', 'pDC.RM', 'Stromal.RM', 'Platelet.RM', 'Mesothelial.RM', 'ActiveAvEp.RM', 'Myelocytes.RM', 'Myofibroblast.RM', 'Fibroblast.RM', 'Hepatocyte.RM')
  return(RunScGateForModels(
    seuratObj = seuratObj,
    modelNames = c(mn, 'PlasmaCell.RM', 'NeutrophilLineage.RM'),
    consensusModels = mn,
    labelRename = c(
      Bcell.RM = 'Bcell',
      Tcell.RM = 'T_NK',
      NK.RM = 'T_NK',
      Myeloid.RM = 'Myeloid',
      AvEp.RM = 'Epithelial',
      Epithelial.RM = 'Epithelial',
      Erythrocyte.RM = 'Erythrocyte',
      pDC.RM = 'Myeloid',
      Stromal.RM = 'Stromal',
      Platelet.RM = 'Platelet', 
      Mesothelial.RM = 'Epithelial',
      ActiveAvEp.RM = 'Epithelial',
      Myelocytes.RM = 'Myeloid',
      Myofibroblast.RM = 'Stromal',
      Fibroblast.RM = 'Stromal',
      Hepatocyte.RM = 'Epithelial'
    ),
    min.cells = min.cells,
    assay = assay,
    pos.thr = pos.thr,
    neg.thr = neg.thr,
    ncores = ncores,
    genes.blacklist = genes.blacklist,
    dropAmbiguousConsensusValues = dropAmbiguousConsensusValues
  ))
}

#' @title Run scGate for models
#'
#' @description Helper function to run scGate, iterating the provided models and generating a consensus field
#' @param seuratObj The seurat object
#' @param modelNames A vector of model names to run. They are assumed to be non-overlapping populations
#' @param min.cells Passed directly to scGate::scGate. Stop iterating if fewer than this number of cells is left
#' @param assay Passed directly to scGate::scGate. Seurat assay to use
#' @param pos.thr Passed directly to scGate::scGate. Minimum UCell score value for positive signatures
#' @param neg.thr Passed directly to scGate::scGate. Maximum UCell score value for negative signatures
#' @param ncores Passed directly to scGate::scGate. Number of processors for parallel processing (requires future.apply)
#' @param genes.blacklist Passed directly to scGate::scGate. Genes blacklisted from variable features. The default loads the list of genes in scGate::genes.blacklist.default; you may deactivate blacklisting by setting genes.blacklist=NULL
#' @param labelRename An optional list that maps the model name to the final label that should be used in the seurat object. for exmaple: list(Tcell = 'T_NK', NK = 'T_NK'), would re-label cells classified as either 'Tcell' or 'NK' by those models to one common label of T_NK
#' @param dropAmbiguousConsensusValues If true, any consensus calls that are ambiguous will be set to NA
#' @param consensusModels An optional list of model names to consider for the consensus call. This allows many models to be run, yet only consider a subset when creating the consensus call. This might be useful if some models overlap or produce false-positives.
#'
#' @export
RunScGateForModels <- function(seuratObj, modelNames, min.cells = 30, assay = 'RNA', pos.thr = 0.13, neg.thr = 0.13, ncores = 1, genes.blacklist = 'default', labelRename = NULL, dropAmbiguousConsensusValues = FALSE, consensusModels = NULL) {
  fieldsToConsiderForConsensus <- c()

  hasRanks <- 'UCellRanks' %in% names(seuratObj@assays)

  for (modelName in modelNames){
    print(paste0('Running model: ', modelName))
    cellLabel <- modelName

    fn <- paste0(modelName, '.is.pure')
    seuratObj <- RunScGate(seuratObj = seuratObj,
              model = modelName,
              min.cells = min.cells,
              assay = assay,
              pos.thr = pos.thr,
              neg.thr = neg.thr,
              ncores = ncores,
              output.col.name = fn,
              genes.blacklist = genes.blacklist,
              doPlotUCellScores = FALSE,
              keep.ranks = TRUE
    )

    if (all(is.null(consensusModels)) || modelName %in% consensusModels) {
      fieldsToConsiderForConsensus <- c(fieldsToConsiderForConsensus, fn)
    }

    seuratObj@meta.data[[fn]] <- as.character(seuratObj@meta.data[[fn]])
    seuratObj@meta.data[[fn]] <- ifelse(seuratObj@meta.data[[fn]] == 'Pure', yes = cellLabel, no = NA)
  }

  if (!hasRanks) {
    seuratObj@assays[['UCellRanks']] <- NULL
  }

  # Remove intermediate fields:
  toDrop <- names(seuratObj@meta.data)[grepl(names(seuratObj@meta.data), pattern = 'is.pure.level')]
  if (length(toDrop) > 0) {
    for (fn in toDrop) {
      seuratObj@meta.data[fn] <- NULL
    }
  }

  .PlotUCellScores(seuratObj)

  # TODO: should we consider UCell thresholds or the delta between the top two calls?
  dat <- seuratObj@meta.data[,fieldsToConsiderForConsensus, drop = FALSE]
  seuratObj$scGateRaw <- sapply(1:nrow(dat), function(idx) {
    vals <- unlist(dat[idx, fieldsToConsiderForConsensus, drop = T])
    vals <- unique(vals[!is.na(vals)])
    if (length(vals) == 0) {
      return(NA)
    }

    return(paste0(sort(unique(vals)), collapse = ','))
  })

  uniqueValues <- unique(as.character(seuratObj$scGateRaw))
  uniqueValues <- uniqueValues[!is.na(uniqueValues)]

  seuratObj$scGateConsensus <- as.character(seuratObj$scGateRaw)
  seuratObj$scGateRaw <- naturalsort::naturalfactor(seuratObj$scGateRaw)

  if (!all(is.null(labelRename)) && length(uniqueValues) > 0) {
    updatedValues <- sapply(uniqueValues, function(vals){
      vals <- unlist(strsplit(vals, split = ','))
      vals <- sapply(vals, function(x){
        if (x %in% names(labelRename)) {
          x <- labelRename[[x]]
        }

        return(x)
      })

      vals <- unique(vals[!is.na(vals)])
      if (length(vals) == 0) {
        return(NA)
      }

      return(paste0(sort(unique(vals)), collapse = ','))
    })

    for (x in 1:length(uniqueValues)) {
      if (is.na(uniqueValues[[x]]) || uniqueValues[[x]] == updatedValues[[x]]) {
        next
      }

      print(paste0('Renaming: ', uniqueValues[x], ' to ', updatedValues[x]))
      seuratObj$scGateConsensus[seuratObj$scGateConsensus == uniqueValues[[x]]] <- updatedValues[[x]]
    }
    seuratObj$scGateConsensus <- naturalsort::naturalfactor(seuratObj$scGateConsensus)
  } else {
    seuratObj$scGateConsensus <- seuratObj$scGateRaw
  }

  if (dropAmbiguousConsensusValues) {
    toDrop <- grepl(seuratObj$scGateConsensus, pattern = ',')
    if (sum(toDrop) > 0) {
      print('Dropping the following ambiguous consensus labels:')
      print(sort(table(seuratObj$scGateConsensus[toDrop]), decreasing = T))

      seuratObj$scGateConsensus[toDrop] <- NA
    }
  }

  seuratObj$scGateConsensus <- naturalsort::naturalfactor(seuratObj$scGateConsensus)

  if (length(names(seuratObj@reductions)) > 0) {
    print(Seurat::DimPlot(seuratObj, group.by = 'scGateConsensus'))
  }

  print(ggplot(seuratObj@meta.data, aes(x = scGateConsensus, fill = scGateConsensus)) +
    geom_bar(color = 'black') +
    egg::theme_presentation(base_size = 12) +
    ggtitle('scGate Consensus') +
    labs(x = 'scGate Call', y = '# Cells') +
    theme(
      legend.position = 'none',
      axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5)
    )
  )

  return(seuratObj)
}