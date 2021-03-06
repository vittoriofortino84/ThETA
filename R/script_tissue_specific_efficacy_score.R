#'Weighted Shortest Paths compiled between a Gene and Disease-associated Genes
#'
#'Determine weighted shortest paths connecting a gene to specified disease-associated genes within relevant tissue-specific PPIs.
#'
#'This function implements the core of the tissue-specific score described in \insertRef{Failli2019}{ThETA}.
#'
#'@param disease_genes character vector containing the IDs of the genes related to a particular disease.
#'Gene IDs are expected to match with those provided in \code{ppi_network} and \code{tissue_expr_data}.
#'@param ppi_network a matrix or a data frame with at least two columns
#'reporting the ppi connections (or edges). Each line corresponds to a direct interaction.
#'Columns give the gene IDs of the two interacting proteins.
#'@param directed_network logical indicating whether the PPI is directed.
#'@param tissue_expr_data a numeric matrix or data frame indicating expression significances
#'in the form of Z-scores. Columns are tissues and rows are genes; colnames and rownames must be provided.
#'Gene IDs are expected to match with those provided in \code{ppi_network}.
#'@param dis_relevant_tissues a named numeric vector indicating the significances of disease-tissue associations in the form of Z-scores.
#'Names correspond to tissues.
#'@param W a list of discretized Borda-aggregated rankings for each tissue as the one compiled by \code{get_node_centrality}.
#'@param cutoff numeric value indicating the cut-off for the disease-associated tissue scores.
#'@param verbose logical indicating whether the messages will be displayed or not in the screen.
#'@return A list of two score objects:\cr
#'        - \strong{shortest_paths}: a shortest path score for each pair <gene, tissue>;\cr
#'        - \strong{shortest_paths_avg}: average of shortest path scores compiled from all relavant tissues.
#'@export
#'@importFrom Rdpack reprompt
#'@importFrom igraph E graph_from_edgelist distances
#'@importFrom scales rescale
weighted.shortest.path <- function(disease_genes, ppi_network, directed_network = F,
                                   tissue_expr_data, dis_relevant_tissues, W, cutoff = 1.6,
                                   verbose=F) {
  #
  if(is.null(rownames(tissue_expr_data))|is.null(colnames(tissue_expr_data))){
    stop('Both colnames and rownames for tissue_expr_data must be provided.')
  }
  for(i in 1:2) ppi_network[,i] <- as.character(ppi_network[,i])
  ppi_network <- ppi_network[!duplicated(ppi_network[,1:2]),]
  ppi_network_size <- nrow(ppi_network)
  if(directed_network) idx <- ppi_network[,1]%in%rownames(tissue_expr_data)
  else idx <- ppi_network[,1]%in%rownames(tissue_expr_data) & ppi_network[,2]%in%rownames(tissue_expr_data)
  ppi_network <- ppi_network[idx,]
  if(nrow(ppi_network)==0) stop('No corresponding IDs between ppi_network and tissue_expr_data.')
  else if(ppi_network_size!=nrow(ppi_network)){
    if(verbose) print(paste(nrow(ppi_network),'out of',ppi_network_size,'network edges selected.', sep=' '))
  }
  if(!directed_network){
    #if(verbose) print('Undirect network. Converting to direct network...')
    ppi_network_rev <- ppi_network[,c(2:1)]
    colnames(ppi_network_rev) <- colnames(ppi_network)[1:2]
    ppi_network <- rbind(ppi_network[,1:2],ppi_network_rev)
  }
  disease_genes_size <- length(disease_genes)
  disease_genes <- intersect(disease_genes,ppi_network[,2])
  if(length(disease_genes)==0) stop('No disease-associated ID match with ppi_network and tissue_expr_data!')
  else if( disease_genes_size!=length(disease_genes)){
    if(verbose) print(paste(length(disease_genes),'disease-associated IDs are reachable from the network.',sep=' '))
  }
  tissue_expr_data <- scales::rescale(tissue_expr_data,c(1,.Machine$double.eps))
  g <- igraph::graph_from_edgelist(as.matrix(ppi_network[,1:2]), directed=T)
  if(is.vector(dis_relevant_tissues) == FALSE) stop('Argument dis_relevant_tissues is not a vector!')
  if(is.null(names(dis_relevant_tissues))) stop('Names for dis_relevant_tissues must be provided!')
  # selecting relevenat tissues
  sign_tiss <- names(which(dis_relevant_tissues >= cutoff))
  if(length(sign_tiss) != 0){
    if(verbose) print(paste(length(sign_tiss),' tissue/s significant for given disease.',sep=''))
    target_path_mean <- NULL
    sh.path <- list()
    for(i in 1:length(sign_tiss)) {
      if (verbose) print(paste("Compiling the tissue-specific efficacy scores for disease-genes in ", sign_tiss[i], ".", sep=""))
      igraph::E(g)$weight <- tissue_expr_data[ppi_network[,1],sign_tiss[i]]
      sh.path[[i]] <- igraph::distances(g, to=disease_genes, mode =  "out", weights = NULL, algorithm = "dijkstra")
    }
    #sh.path <- lapply(sign_tiss, function(i){
    #  igraph::E(g)$weight <- tissue_expr_data[ppi_network[,1],i]
    #  igraph::distances(g, to=disease_genes, mode =  "out", weights = NULL, algorithm = "dijkstra")
    #})
    names(sh.path) <- sign_tiss
    sh.path <- lapply(sh.path,function(x){
        x[is.infinite(x)]<-(3*max(x[which(is.finite(x))],na.rm = TRUE))
        x
      })
    # weighting shortest paths according to disease-associeted genes discrete values
    new_sh.path <- mapply(function(x,y) t(x)*y[colnames(x)],sh.path, W[sign_tiss], SIMPLIFY=F)
    # averaging shortest paths across the disease-associated genes and the disease-relevant tissues
    target_path <- sapply(new_sh.path,colMeans)
    target_path_mean <- rowMeans(target_path)
    return(list(shortest_paths = target_path,
                shortest_paths_avg = target_path_mean))
  }
  else stop('No tissue significant for given disease!')
}

#'Compile tissue-specific scores for a given disease.
#'
#'Determine the tissue-specific scores for genes connected to disease-associated genes within relevant tissue-specific PPIs.
#'
#'This function implements the tissue-specific efficacy estimates of target-disease associations described in \insertRef{Failli2019}{ThETA}.
#'This function use \code{weighted.shortest.path} to compile weighted shortest paths connecting a gene to specified
#'disease-associated genes within relevant tissue-specific PPIs. The interquartile range (IQR) is applied to remove outliers
#'and the final set of efficacy scores are rescaled between 1 and 0, with 1 indicating the most effective targets.
#'
#'@param disease_genes character vector containing the IDs of the genes related to a particular disease.
#'Gene IDs are expected to match with those provided in \code{ppi_network} and \code{tissue_expr_data}.
#'@param disease_gene_list a list of disease-associated genes. Each element of the list is a character vector
#'containing the IDs of the genes related to a particular disease.
#'@param ppi_network a matrix or a data frame with at least two columns
#'reporting the ppi connections (or edges). Each line corresponds to a direct interaction.
#'Columns give the gene IDs of the two interacting proteins.
#'@param directed_network logical indicating whether the PPI is directed.
#'@param tissue_expr_data a numeric matrix or data frame indicating expression significances
#'in the form of Z-scores. Columns are tissues and rows are genes; colnames and rownames must be provided.
#'Gene IDs are expected to match with those provided in \code{ppi_network}.
#'@param dis_relevant_tissues a named numeric vector in case of \code{tissue.specific.scores} or a
#'numeric matrix in case of \code{list.tissue.specific.scores} indicating the significances of
#'disease-tissue associations in the form of Z-scores. Vector names correspond to tissue; matrix colnames and
#'rownames correspond to tissues and diseases, respectively. Names must be provided.
#'@param W a list of discretized Borda-aggregated rankings for each tissue as the one compiled by \code{get_node_centrality}.
#'@param cutoff numeric value indicating the cut-off for the disease-associated tissue scores.
#'@param verbose logical indicating whether the messages will be displayed or not in the screen.
#'@param parallel an integer indicating how many cores will be registered for parallel computation.
#'@return a data frame or a list of data frames containing tissue specific scores.
#'@export
#'@importFrom Rdpack reprompt
#'@importFrom scales rescale
#'@importFrom stats quantile
tissue.specific.scores <- function(disease_genes, ppi_network, directed_network = F,
                                   tissue_expr_data,  dis_relevant_tissues, W, cutoff = 1.6,
                                   verbose = FALSE) {
  if(is.null(disease_genes) | is.null(tissue_expr_data) | is.null(ppi_network) | is.null(dis_relevant_tissues))
    stop('Incomplete data input.')
  # compile the wsp
  wsp_list = weighted.shortest.path(disease_genes, ppi_network,
                                    directed_network, tissue_expr_data,
                                    dis_relevant_tissues, W, cutoff, verbose)
  tissue_scores <- apply(wsp_list$shortest_paths, 2, function(x) {
    q <- stats::quantile(x)
    outliers <- q[4]+(1.5*(q[4]-q[2]))
    ts <- scales::rescale(x, from=c(min(x), outliers), to=c(1,0))
    ts[ts< 0] <- 0
    ts
  })
  dt <- data.frame(tissue_scores, avg_tissue_score = rowMeans(tissue_scores[,,drop=F]))
  return(dt)
}
#'@rdname tissue.specific.scores
#'@export
#'@importFrom stats setNames
#'@importFrom scales rescale
#'@importFrom snow makeCluster stopCluster
#'@importFrom doParallel registerDoParallel
#'@importFrom foreach foreach %dopar%
list.tissue.specific.scores <- function(disease_gene_list, ppi_network, directed_network = F,
                                        tissue_expr_data,  dis_relevant_tissues, W, cutoff = 1.6,
                                        verbose = FALSE, parallel = NULL) {
  if(is.list(disease_gene_list) == FALSE) stop('Argument disease_gene_list is not a list!')
  if(is.null(names(disease_gene_list))) stop('Names for disease_gene_list must be provided!')
  if(is.matrix(dis_relevant_tissues) == FALSE) stop('Argument dis_relevant_tissues is not a matrix!')
  if(is.null(rownames(dis_relevant_tissues))|is.null(colnames(dis_relevant_tissues))){
    stop('Both colnames and rownames for dis_relevant_tissues must be provided!')
  }
  common_diseases <- intersect(names(disease_gene_list), rownames(dis_relevant_tissues))
  if(length(common_diseases)==0) stop('No diseases in common between disease_gene_list and dis_relevant_tissues!')
  else if(length(common_diseases) != length(names(disease_gene_list))){
    if(verbose) print(paste(length(common_diseases),'diseases in common between disease_gene_list and dis_relevant_tissues.',sep=' '))
  }
  tissue_scores <- NULL
  if(!is.null(parallel)) {
    dis = NULL
    cl <- snow::makeCluster(parallel)
    doParallel::registerDoParallel(cl)
    `%dopar%` <- foreach::`%dopar%`
    wsp <- foreach::foreach(dis=common_diseases,
                            .export = 'weighted.shortest.path',
                            .final = function(i) setNames(i, common_diseases)) %dopar% {
      weighted.shortest.path(disease_gene_list[[dis]], 
                             ppi_network, 
                             directed_network, 
                             tissue_expr_data, 
                             dis_relevant_tissues[dis,], 
                             W, cutoff = cutoff)}
    snow::stopCluster(cl)
  }
  else {
    warning("A parallel computation is highly recommended",immediate. = T)
    wsp <- sapply(common_diseases, function(i) weighted.shortest.path(disease_gene_list[[i]], ppi_network, directed_network, tissue_expr_data, dis_relevant_tissues[i,], W, cutoff = cutoff),simplify=F)
  }
  wsp <- do.call(function(...)mapply(list,...,SIMPLIFY = F),wsp)
  tissue_scores <- lapply(wsp$shortest_paths, function(x) apply(x, 2, function(y) {
    q <- quantile(y)
    outliers <- q[4]+(1.5*(q[4]-q[2]))
    ts <- scales::rescale(y, from=c(min(x), outliers), to=c(1,0))
    ts[ts< 0] <- 0
    ts
  }))
  tissue_scores <- lapply(tissue_scores,function(x)data.frame(x, avg_tissue_score = rowMeans(x[,,drop=F])))
  return(tissue_scores)
}


#'Compile tissue-specific networks and, within these, set of genes that are relevant for the selected targets.
#'
#'Given a set of gene targets, it builds the corresponding tissue-specific networks, the set of genes linking the targets to
#'disease genes, a set of genes tightly connected to all targets.
#'
#'The top targets are used to re-build the shortest paths with the disease-relevant genes in tissue-specific networks.
#'The shortest paths linkining a top target to disease genes are merged and the resulting set of nodes/genes are giving in output.
#'Moreover, random walk with restart is utilized to identify a set of genes that is tightly connected to the targets.
#'
#'@param tissue_scores a data.frame as the one compiled by \code{get.tissue.specific.scores}
#'@param disease_genes character vector containing the IDs of the genes related to a particular disease.
#'Gene IDs are expected to match with those provided in \code{ppi_network} and \code{tissue_expr_data}.
#'@param ppi_network a matrix or a data frame with at least two columns
#'reporting the ppi connections (or edges). Each line corresponds to a direct interaction.
#'Columns give the gene IDs of the two interacting proteins.
#'@param directed_network logical indicating whether the PPI is directed.
#'@param tissue_expr_data a numeric matrix or data frame indicating expression significances
#'in the form of Z-scores. Columns are tissues and rows are genes; colnames and rownames must be provided.
#'Gene IDs are expected to match with those provided in \code{ppi_network}.
#'@param top_targets character vector indicating a list of ENTREZ id to be used for the slection of the shortest paths.
#'@param rwr_restart the restart probability used for RWR. See \code{dnet::dRWR} for more details.
#'@param rwr_norm the way to normalise the adjacency matrix of the input graph. See \code{dnet::dRWR} for more details.
#'@param rwr_cutoff the cuoff value to select the most visited genes. 
#'@param verbose logical indicating whether the messages will be displayed or not in the screen.
#'@return a list of four objects: \cr
#'        - \strong{tsn}: a list of tissue-specific networks;\cr
#'        - \strong{shp}: a list of gene sets, each gene set indicates the genes connecting a target to all disease genes;\cr
#'        - \strong{tsn}: a list of gene sets, each gene set represents the set of genese that are closely related to the set of targets;\cr
#'        - \strong{universe}: the total number of genes in the tissue-specific networks.
#'@export
#'@importFrom dnet dRWR
#'@importFrom igraph V
#'@importFrom igraph E
#'@importFrom igraph shortest_paths
build.tissue.specific.networks <- function(tissue_scores, disease_genes, ppi_network,
                                           directed_network = F, tissue_expr_data,
                                           top_targets = NULL, rwr_restart = 0.75,
                                           rwr_norm = "quantile", rwr_cutoff = 0.001,
                                           verbose = FALSE){
  # check
  if(is.null(top_targets)) stop('Please specifiy a set of targets (ENTREZ ids)!')
  if(!is.character(ppi_network[,1])) ppi_network[,1] <- as.character(ppi_network[,1])
  if(!is.character(ppi_network[,2])) ppi_network[,2] <- as.character(ppi_network[,2])
  ppi_network <- ppi_network[!duplicated(ppi_network[,1:2]),]
  ppi_network_node<-unique(unlist(ppi_network[,1:2]))
  universe <- intersect(ppi_network_node,rownames(tissue_expr_data))
  if(length(universe)==0) stop('No corresponding IDs between ppi_network and tissue_expr_data!')
  else if(length(universe)!=length(ppi_network_node)|
          length(universe)!=nrow(tissue_expr_data)){
    if (verbose) print(paste(length(universe),'IDs in common between ppi_network and tissue_expr_data will be considered.', sep=' '))
    tissue_expr_data<-tissue_expr_data[universe,]
  }
  ## scale tissue expression scores
  tissue_expr_data <- scales::rescale(tissue_expr_data,c(1,.Machine$double.eps))
  ## select the sign tissues
  sign_tiss <- colnames(tissue_scores)[-ncol(tissue_scores)]
  tissue_spec_network <- list()
  shp_top_genes <- list()
  rwr_top_genes <- list()
  for(i in 1: length(sign_tiss)) {
    if (verbose) print(paste("Building the tissue-specific gene network for ", sign_tiss[i], ".", sep=""))
    g <- igraph::graph_from_edgelist(as.matrix(ppi_network[,1:2]), directed=T)
    igraph::E(g)$weight <- tissue_expr_data[ppi_network[,1], sign_tiss[i]]
    if (verbose) print(paste("Compiling the shortest paths between disease-genes and top-(", length(top_targets),") gene targets.", sep = ""))
    # select disease genes active in this tissue and search for shortest paths
    tissue_disease_genes <- intersect(disease_genes, igraph::V(g)$name)
    shp_top_genes[[length(shp_top_genes) + 1]] <- lapply(top_targets, function(x) {
      ss = igraph::distances(g, v=x, to=tissue_disease_genes, mode =  "out", weights = NULL, algorithm = "dijkstra")
      if(verbose) print(paste("Targets ", x, " cannot reach ", length(which(is.infinite(ss)))," nodes", sep=""))
      suppressWarnings(selected_nodes <- unique(unlist(igraph::shortest_paths(g, from=x, to=tissue_disease_genes, mode =  "out", weights = NULL, output='vpath')$vpath)))
      igraph::V(g)$name[selected_nodes]
    })
    names(shp_top_genes[[length(shp_top_genes)]]) <- top_targets
    # apply random walk on the top targets
    aSeeds <- rep(0, length(igraph::V(g)$name))
    aSeeds[which((igraph::V(g)$name%in%top_targets) == TRUE)] <- 1
    setSeeds <- data.frame(aSeeds)
    rownames(setSeeds) <- igraph::V(g)$name
    if (verbose) print("Identifying genes tightly connected to the top-n targets.")
    rwr_top_genes[[length(rwr_top_genes)+1]] <- suppressMessages(as.numeric(dnet::dRWR(g, normalise = "none", 
                                                                                       setSeeds = setSeeds, 
                                                                                       restart = rwr_restart,
                                                                                       normalise.affinity.matrix = rwr_norm, 
                                                                                       parallel = FALSE, 
                                                                                       multicores = NULL, 
                                                                                       verbose = FALSE)))
    names(rwr_top_genes[[length(rwr_top_genes)]]) = igraph::V(g)$name
    rwr_top_genes[[length(rwr_top_genes)]] = names(rwr_top_genes[[length(rwr_top_genes)]])[which(rwr_top_genes[[length(rwr_top_genes)]] >= rwr_cutoff)]
    #
    tissue_spec_network[[length(tissue_spec_network) + 1]] = g
  }
  names(rwr_top_genes) <- sign_tiss
  names(shp_top_genes) <- sign_tiss
  names(tissue_spec_network) <- sign_tiss
  return(list("tsn"=tissue_spec_network, "shp" = shp_top_genes, "rwr" = rwr_top_genes, "universe" = universe))
}

#'Over-Representation Analysis.
#'
#'It compiles the over-representation analysis for each gene set in the input list.
#'
#'
#'@param input a list of charcater vectors representing gene sets.
#'@param databases character vector indicating the biological annotations to be used for the ORA.
#'Possible values are: GO, KEGG and REACTOME enrichment functions.
#'@param orgdb_go a character specifying the organism for GO. Deafault value is \code{org.Hs.eg.db}.
#'@param orgdb_kegg a character specifying the organism for KEGG. Deafault value is \code{hsa}.
#'@param apval a number indicating the cutoff for the adjusted pvalue.
#'@param verbose logical indicating whether the messages will be displayed or not in the screen.
#'@return a list or ORA results.
#'@export
#'@importFrom clusterProfiler enrichKEGG
#'@importFrom clusterProfiler enrichGO
#'@importFrom ReactomePA enrichPathway
generate.ora.data <- function(input, databases = c("GO", "KEGG"),
                              orgdb_go = 'org.Hs.eg.db', orgdb_kegg = 'hsa',
                              apval = 0.01, verbose = TRUE) {
  list_annots <- list()
  annots <- c()
  for(i in 1:length(input)) {
    if("GO" %in% databases) {
      list_annots[[length(list_annots) + 1]] <- clusterProfiler::enrichGO(unique(unlist(input[[i]])),
                                                                          orgdb_go, ont = "BP",
                                                                          pvalueCutoff = apval,
                                                                          universe = input$universe)
      annots <- c(annots,"GO")
      if(verbose) print(paste("ORA completed for GO-", names(input)[i], ".", sep=""))
    }
    if("KEGG" %in% databases) {
      list_annots[[length(list_annots) + 1]] <- clusterProfiler::enrichKEGG(unique(unlist(input[[i]])),
                                                                            organism = orgdb_kegg,
                                                                            keyType = "kegg",
                                                                            pvalueCutoff = apval,
                                                                            universe = input$universe)
      annots <- c(annots,"KEGG")
      if(verbose) print(paste("ORA completed for KEGG-", names(input)[i], ".", sep=""))
    }
    if("REACTOME" %in% databases) {
      list_annots[[length(list_annots) + 1]] <- ReactomePA::enrichPathway(unique(unlist(input[[i]])),
                                                                          pvalueCutoff = apval,
                                                                          readable = T)
      annots <- c(annots,"REACTOME")
      if(verbose) print(paste("ORA completed for REACTOME-", names(input)[i], ".", sep=""))
    }
  }
  names(list_annots) <- paste(annots, names(input), sep="-")
  return(list_annots)
}


#'Generate plots for the visualization of ORA results.
#'
#'Annotation plots generated with the R package 'enrichplot'.
#'
#'@param ora_data a list of ORA results.
#'@param set_plots character vector indicating the types of plots to be generated.
#'Possible values are: dotplot, emapplot, cnetplot and upsetplot.
#'@param showCategory number of enriched terms to display.
#'@param font_size text size in pts.
#'@return a set of plot for each ORA result.
#'@export
#'@importFrom enrichplot dotplot
#'@importFrom enrichplot emapplot
#'@importFrom enrichplot cnetplot
#'@importFrom enrichplot upsetplot
#'@importFrom ggplot2 theme
#'@importFrom ggplot2 element_text
generate.ora.plots <- function(ora_data, set_plots = c("dotplot", "emapplot", "cnetplot", "upsetplot"),
                               showCategory = 20, font_size = 8){
  list_plots <- list()
  plots <- c()
  for(i in 1:length(ora_data)) {
    if("dotplot" %in% set_plots) {
      list_plots[[length(list_plots)+1]] <- enrichplot::dotplot(ora_data[[i]], showCategory = showCategory, font.size = font_size) +
        ggplot2::theme(legend.title=ggplot2::element_text(size=font_size),
                       legend.text=ggplot2::element_text(size=font_size))
      plots <- c(plots, paste("dotplot",names(ora_data)[i],sep="-"))
    }
    if("emapplot" %in% set_plots) {
      list_plots[[length(list_plots)+1]] <- enrichplot::emapplot(ora_data[[i]], showCategory = showCategory) +
        ggplot2::theme(legend.title=ggplot2::element_text(size=font_size),
                       legend.text=ggplot2::element_text(size=font_size))
      plots <- c(plots, paste("emapplot",names(ora_data)[i],sep="-"))
    }
    if("cnetplot" %in% set_plots) {
      list_plots[[length(list_plots)+1]] <- enrichplot::cnetplot(ora_data[[i]], showCategory = showCategory) +
        ggplot2::theme(legend.title=ggplot2::element_text(size=font_size),
                       legend.text=ggplot2::element_text(size=font_size))
      plots <- c(plots, paste("cnetplot",names(ora_data)[i],sep="-"))
    }
    if("upsetplot" %in% set_plots) {
      list_plots[[length(list_plots)+1]] <- enrichplot::upsetplot(ora_data[[i]]) +
        ggplot2::theme(legend.title=ggplot2::element_text(size=font_size),
                       legend.text=ggplot2::element_text(size=font_size))
      plots <- c(plots, paste("upsetplot",names(ora_data)[i],sep="-"))
    }
  }
  print(plots)
  names(list_plots) <- plots
  return(list_plots)
}

#'Generate PubMed Central Trend plots.
#'
#'It uses the pmcplot function from R package 'enrichplot' to generate gene-based trend plots.
#'
#'@param list_genes a list of gene names (SYMBOLS).
#'@param pubmed period of query in the unit of year.
#'@param font_size text size in pts.
#'@return a PubMed-trend plot.
#'@export
#'@importFrom enrichplot pmcplot
#'@importFrom ggplot2 theme
#'@importFrom ggplot2 theme_minimal
#'@importFrom ggplot2 element_text
novelty.plots <- function(list_genes, pubmed = c(2010,2019), font_size = 8){
  plot <- enrichplot::pmcplot(list_genes, pubmed[1]:pubmed[2]) + ggplot2::theme_minimal() +
    ggplot2::theme(legend.title=ggplot2::element_text(size=font_size),
                   legend.text=element_text(size=font_size),
                   axis.text.x = element_text(size=font_size),
                   axis.text.y = element_text(size=font_size))
  return(plot)
}

