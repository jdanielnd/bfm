#' Sparse Latent Factor Model
#'
#' This function is used to fit a Bayesian sparse
#' latent factor model.
#' 
#' @references
#' 1. Duarte, J. D. N. and Mayrink, V. D. (2015). Factor analysis with mixture modeling to evaluate coherent patterns in microarray data. In Interdisciplinary Bayesian Statistics, volume 118 of Springer Proceedings in Mathematics & Statistics, pages 185-195. Springer International Publishing.
#'
#' @param x matrix with the pre-processed data
#' @param ite number of iterations of the MCMC algorithm
#' @param a prior shape parameter for Gamma distribution 
#' @param b prior scale parameter for Gamma distribution
#' @param gamma_a prior parameter for Beta distribution
#' @param gamma_b prior parameter for Beta distribution
#' @param omega_0 prior variance of the spike component
#' @param omega_1 prior variance of the slab component
#' @param burnin burn-in size
#' @param degenerate use the degenerate version of mixture
#' @return x: data matrix
#' @return p_star: matrix of MCMC chains for p_star parameter
#' @return alpha: summary table of MCMC chains for alpha parameter
#' @return lambda: summary table of MCMC chains for lambda parameter
#' @return sigma: summary table of MCMC chains for sigma parameter
#' @return classification: classification of each alpha (`present`, `marginal`, `absent`)
#' @export
#' @importFrom coda as.mcmc
#' @importFrom Rcpp evalCpp
#' @useDynLib slfm
#' @examples
#' mat <- matrix(rnorm(2000), nrow = 20)
#' slfm(mat, ite = 1000)
slfm <- function(
  x, a = 2.1, b = 1.1, gamma_a = 1, gamma_b = 1,
  omega_0 = 0.01, omega_1 = 10, sample = 1000, burnin = round(0.25*sample), lag = 1, degenerate = FALSE) {
  
  ite <- sample + burnin

  # Convert the x input to numeric matrix
  x <- data.matrix(x)

  if(degenerate) {
    res <- slfm_MDN(x, a, b, gamma_a, gamma_b, omega_1, burnin, lag, sample)
  } else {
    res <- slfm_MNN(x, a, b, gamma_a, gamma_b, omega_0, omega_1, burnin, lag, sample)
  }

  after_burnin <- (burnin + 1):ite

  p_star_matrix <- coda::as.mcmc(res[["qstar"]][after_burnin,])
  hpds_p_star <- coda::HPDinterval(p_star_matrix)
  stats_p_star <- summary(p_star_matrix)$statistics
  alpha_clas <- format_classification(class_interval(hpds_p_star))
  alpha_clas_mean <- class_mean(stats_p_star)

  alpha_matrix <- coda::as.mcmc(res[["alpha"]][after_burnin,])

  table_alpha <- alpha_estimation(res[["alpha"]][after_burnin,], alpha_clas_mean, res[["qstar"]][after_burnin,])

  lambda_matrix <- coda::as.mcmc(res[["lambda"]][after_burnin,])
  stats_lambda <- summary(lambda_matrix)$statistics
  hpds_lambda <- coda::HPDinterval(lambda_matrix)
  table_lambda <- cbind(stats_lambda, hpds_lambda)[,-4]
  colnames(table_lambda)[4:5] = c("Upper HPD", "Lower HPD")

  sigma_matrix <- coda::as.mcmc(res[["sigma2"]][after_burnin,])
  stats_sigma <- summary(sigma_matrix)$statistics
  hpds_sigma <- coda::HPDinterval(sigma_matrix)
  table_sigma <- cbind(stats_sigma, hpds_sigma)[,-4]
  colnames(table_sigma)[4:5] = c("Upper HPD", "Lower HPD")

  z_matrix <- coda::as.mcmc(res[["z"]][after_burnin,])

  obj <- list(
    x = x,
    p_star = p_star_matrix,
    alpha = table_alpha,
    lambda = table_lambda,
    sigma = table_sigma,
    alpha_matrix = alpha_matrix,
    lambda_matrix = lambda_matrix,
    sigma_matrix = sigma_matrix,
    z_matrix = z_matrix,
    classification = alpha_clas)
  class(obj) <- "slfm"
  obj
}

print.slfm <- function(x) {
  cat("SLFM object", "\n")
  cat("\n")
  cat("Dimensions","\n")
  cat("- alpha:", nrow(x$alpha),"\n")
  cat("- lambda:", nrow(x$lambda),"\n")
  cat("\n")
  cat("Classification:","\n")
  print(x$classification)
}

alpha_estimation <- function(x, alpha_clas, p_star_matrix) {
  table_list <- lapply(1:length(alpha_clas), function(i) {
    chain_indicator <- p_star_matrix[, i] > 0.5
    if(alpha_clas[i]) {
      chain <- x[chain_indicator, i]
    } else {
      chain <- x[!chain_indicator, i]
    }
    chain.mcmc <- coda::as.mcmc(chain)
    stats <- summary(chain.mcmc)$statistics
    hpds <- coda::HPDinterval(chain.mcmc)
    table <- c(stats, hpds)[-4]
  })
  table <- do.call(rbind, table_list)
  colnames(table)[4:5] = c("Upper HPD", "Lower HPD")
  table
}