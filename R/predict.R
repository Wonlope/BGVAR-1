#' @name predict
#' @title Predictions
#' @description A function that computes predictions based on a object of class \code{bgvar}.
#' @param object an object of class \code{bgvar}.
#' @param ... additional arguments.
#' @param n.ahead the forecast horizon.
#' @param save.store If set to \code{TRUE} the full distribution is returned. Default is set to \code{FALSE} in order to save storage.
#' @param verbose If set to \code{FALSE} it suppresses printing messages to the console.
#' @return Returns an object of class \code{bgvar.pred} with the following elements \itemize{
#' \item{\code{fcast}}{ is a K times n.ahead times 5-dimensional array that contains 16\%th, 25\%th, 50\%th, 75\%th and 84\% percentiles of the posterior predictive distribution.}
#' \item{\code{xglobal}}{ is a matrix object of dimension T times N (T # of observations, K # of variables in the system).}
#' \item{\code{n.ahead}}{ specified forecast horizon.}
#' \item{\code{lps.stats}}{ is an array object of dimension K times 2 times n.ahead and contains the mean and standard deviation of the log-predictive scores for each variable and each forecast horizon.}
#' \item{\code{hold.out}}{ if \code{h} is not set to zero, this contains the hold-out sample.}
#' }
#' @examples
#' library(BGVAR)
#' data(eerDatasmall)
#' model.ssvs <- bgvar(Data=eerDatasmall,W=W.trade0012.small,plag=1,draws=100,burnin=100,
#'                     prior="SSVS")
#' fcast <- predict(model.ssvs, n.ahead=8)
#' @importFrom stats rnorm tsp sd
#' @author Maximilian Boeck, Martin Feldkircher, Florian Huber
#' @export
predict.bgvar <- function(object, ..., n.ahead=1, save.store=FALSE, verbose=TRUE){
  start.pred <- Sys.time()
  if(verbose) cat("\nStart computing predictions of Bayesian Global Vector Autoregression.\n\n")
  draws      <- object$args$thindraws
  plag       <- object$args$plag
  xglobal    <- object$xglobal
  x          <- xglobal[(plag+1):nrow(xglobal),]
  S_large    <- object$stacked.results$S_large
  A_large    <- object$stacked.results$A_large
  Ginv_large <- object$stacked.results$Ginv_large
  F.eigen    <- object$stacked.results$F.eigen
  varNames   <- colnames(xglobal)
  cN         <- unique(sapply(strsplit(varNames,".",fixed=TRUE),function(x) x[1]))
  vars       <- unique(sapply(strsplit(varNames,".",fixed=TRUE),function(x) x[2]))
  N          <- length(cN)
  Traw       <- nrow(xglobal)
  bigT       <- nrow(x)
  M          <- ncol(xglobal)
  cons       <- 1
  trend      <- ifelse(object$args$trend,1,0)
  
  varndxv <- c(M,cons+trend,plag)
  nkk     <- (plag*M)+cons+trend
  
  Yn <- xglobal
  Xn <- cbind(.mlag(Yn,plag),1)
  Xn <- Xn[(plag+1):Traw,,drop=FALSE]
  Yn <- Yn[(plag+1):Traw,,drop=FALSE]
  if(trend) Xn <- cbind(Xn,seq(1,bigT))
  
  fcst_t <- array(NA,dim=c(draws,M,n.ahead))
  
  # start loop here
  if(verbose) cat("Start computing...\n")
  if(verbose) pb <- txtProgressBar(min = 0, max = draws, style = 3)
  for(irep in 1:draws){
    #Step I: Construct a global VC matrix Omega_t
    Ginv    <- Ginv_large[irep,,]
    Sig_t   <- Ginv%*%(S_large[irep,,])%*%t(Ginv)
    Sig_t   <- as.matrix(Sig_t)
    zt      <- Xn[bigT,]
    z1      <- zt
    Mean00  <- zt
    Sigma00 <- matrix(0,nkk,nkk)
    y2      <- NULL
    
    #gets companion form
    aux   <- .get_companion(A_large[irep,,],varndxv)
    Mm    <- aux$MM
    Jm    <- aux$Jm
    Jsigt <- Jm%*%Sig_t%*%t(Jm)
    # this is the forecast loop
    for (ih in 1:n.ahead){
      z1      <- Mm%*%z1
      Sigma00 <- Mm%*%Sigma00%*%t(Mm) + Jsigt
      chol_varyt <- try(t(chol(Sigma00[1:M,1:M])),silent=TRUE)
      if(is(chol_varyt,"try-error")){
        yf <- mvrnorm(1,mu=z1[1:M],Sigma00[1:M,1:M])
      }else{
        yf <- z1[1:M]+chol_varyt%*%rnorm(M,0,1)
      }
      y2 <- cbind(y2,yf)
    }
    
    fcst_t[irep,,] <- y2
    if(verbose) setTxtProgressBar(pb, irep)
  }
  
  imp_posterior<-array(NA,dim=c(M,n.ahead,5))
  dimnames(imp_posterior)[[1]] <- varNames
  dimnames(imp_posterior)[[2]] <- 1:n.ahead
  dimnames(imp_posterior)[[3]] <- c("low25","low16","median","high75","high84")
  
  imp_posterior[,,"low25"]  <- apply(fcst_t,c(2,3),quantile,0.25,na.rm=TRUE)
  imp_posterior[,,"low16"]  <- apply(fcst_t,c(2,3),quantile,0.16,na.rm=TRUE)
  imp_posterior[,,"median"] <- apply(fcst_t,c(2,3),quantile,0.50,na.rm=TRUE)
  imp_posterior[,,"high75"] <- apply(fcst_t,c(2,3),quantile,0.75,na.rm=TRUE)
  imp_posterior[,,"high84"] <- apply(fcst_t,c(2,3),quantile,0.84,na.rm=TRUE)
  
  h                        <- object$args$h
  if(h>n.ahead) h            <- n.ahead
  yfull                    <- object$args$yfull
  if(h>0){
    lps.stats                <- array(0,dim=c(M,2,h))
    dimnames(lps.stats)[[1]] <- colnames(xglobal)
    dimnames(lps.stats)[[2]] <- c("mean","sd")
    dimnames(lps.stats)[[3]] <- 1:h
    lps.stats[,"mean",]      <- apply(fcst_t[,,1:h],c(2:3),mean)
    lps.stats[,"sd",]        <- apply(fcst_t[,,1:h],c(2:3),sd)
    hold.out<-yfull[(nrow(yfull)+1-h):nrow(yfull),,drop=FALSE]
  }else{
    lps.stats<-NULL
    hold.out<-NULL
  }
  rownames(xglobal)<-.timelabel(object$args$time)
  
  out <- structure(list(fcast=imp_posterior,
                        xglobal=xglobal,
                        n.ahead=n.ahead,
                        lps.stats=lps.stats,
                        hold.out=hold.out),
                   class="bgvar.pred")
  if(save.store){
    out$pred_store = fcst_t
  }
  if(verbose) cat(paste("\n\nSize of object:", format(object.size(out),unit="MB")))
  end.pred <- Sys.time()
  diff.pred <- difftime(end.pred,start.pred,units="mins")
  mins.pred <- round(diff.pred,0); secs.pred <- round((diff.pred-floor(diff.pred))*60,0)
  if(verbose) cat(paste("\nNeeded time for computation: ",mins.pred," ",ifelse(mins.pred==1,"min","mins")," ",secs.pred, " ",ifelse(secs.pred==1,"second.","seconds.\n"),sep=""))
  return(out)
}

#' @name cond.predict
#' @title Conditional Forecasts
#' @description Function that computes conditional forecasts for Bayesian Vector Autoregressions.
#' @usage cond.predict(constr, bgvar.obj, pred.obj, constr_sd=NULL, verbose=TRUE)
#' @details Conditional forecasts need a fully identified system. Therefore this function utilizes short-run restrictions via the Cholesky decomposition on the global solution of the variance-covariance matrix of the Bayesian GVAR.
#' @param constr a matrix containing the conditional forecasts of size horizon times K, where horizon corresponds to the forecast horizon specified in \code{pred.obj}, while K is the number of variables in the system. The ordering of the variables have to correspond the ordering of the variables in the system. Rest is just set to NA.
#' @param bgvar.obj an item fitted by \code{bgvar}.
#' @param pred.obj an item fitted by \code{predict}. Note that \code{save.store=TRUE} is required as argument!
#' @param constr_sd a matrix containing the standard deviations around the conditional forecasts. Must have the same size as \code{constr}.
#' @param verbose If set to \code{FALSE} it suppresses printing messages to the console.
#' @return Returns an object of class \code{bgvar.pred} with the following elements \itemize{
#' \item{\code{fcast}}{ is a K times n.ahead times 5-dimensional array that contains 16\%th, 25\%th, 50\%th, 75\%th and 84\% percentiles of the conditional posterior predictive distribution.}
#' \item{\code{xglobal}}{ is a matrix object of dimension T times N (T # of observations, K # of variables in the system).}
#' \item{\code{n.ahead}}{ specified forecast horizon.}
#' }
#' @author Maximilian Boeck
#' @examples
#' library(BGVAR)
#' data(eerDatasmall)
#' model.ssvs.eer<-bgvar(Data=eerDatasmall,W=W.trade0012.small,draws=100,burnin=100,
#'                       plag=1,prior="SSVS",eigen=TRUE)
#' 
#' # compute predictions
#' fcast <- predict(model.ssvs.eer,n.ahead=8,save.store=TRUE)
#' 
#' # set up constraints matrix of dimension n.ahead times K
#' constr <- matrix(NA,nrow=fcast$n.ahead,ncol=ncol(model.ssvs.eer$xglobal))
#' colnames(constr) <- colnames(model.ssvs.eer$xglobal)
#' constr[1:5,"US.Dp"] <- model.ssvs.eer$xglobal[76,"US.Dp"]
#' 
#' # add uncertainty to conditional forecasts
#' constr_sd <- matrix(NA,nrow=fcast$n.ahead,ncol=ncol(model.ssvs.eer$xglobal))
#' colnames(constr_sd) <- colnames(model.ssvs.eer$xglobal)
#' constr_sd[1:5,"US.Dp"] <- 0.001
#' 
#' cond_fcast <- cond.predict(constr, model.ssvs.eer, fcast, constr_sd)
#' @references 
#' Jarocinski, M. (2010) \emph{Conditional forecasts and uncertainty about forecasts revisions in vector autoregressions.} Economics Letters, Vol. 108(3), pp. 257-259.
#' 
#' Waggoner, D., F. and T. Zha (1999) \emph{Conditional Forecasts in Dynamic Multivariate Models.} Review of Economics and Statistics, Vol. 81(4), pp. 639-561.
#' @importFrom abind adrop
#' @importFrom stats rnorm
#' @export
cond.predict <- function(constr, bgvar.obj, pred.obj, constr_sd=NULL, verbose=TRUE){
  start.cond <- Sys.time()
  if(!inherits(pred.obj, "bgvar.pred")) {stop("Please provide a `bgvar.predict` object.")}
  if(!inherits(bgvar.obj, "bgvar")) {stop("Please provide a `bgvar` object.")}
  if(verbose) cat("\nStart conditional forecasts of Bayesian Global Vector Autoregression.\n\n")
  #----------------get stuff-------------------------------------------------------#
  plag        <- bgvar.obj$args$plag
  xglobal     <- pred.obj$xglobal
  Traw        <- nrow(xglobal)
  bigK        <- ncol(xglobal)
  bigT        <- Traw-plag
  A_large     <- bgvar.obj$stacked.results$A_large
  F_large     <- bgvar.obj$stacked.results$F_large
  S_large     <- bgvar.obj$stacked.results$S_large
  Ginv_large  <- bgvar.obj$stacked.results$Ginv_large
  F.eigen     <- bgvar.obj$stacked.results$F.eigen
  thindraws   <- length(F.eigen)
  x           <- xglobal[(plag+1):Traw,,drop=FALSE]
  horizon     <- pred.obj$n.ahead
  varNames    <- colnames(xglobal)
  cN          <- unique(sapply(strsplit(varNames,".",fixed=TRUE),function(x)x[1]))
  var         <- unique(sapply(strsplit(varNames,".",fixed=TRUE),function(x)x[2]))
  #---------------------checks------------------------------------------------------#
  if(is.null(pred.obj$pred_store)){
    stop("Please set 'save.store=TRUE' when computing predictions.")
  }
  if(!all(dim(constr)==c(horizon,bigK))){
    stop("Please respecify dimensions of 'constr'.")
  }
  if(!is.null(constr_sd)){
    if(!all(dim(constr_sd)==c(horizon,bigK))){
      stop("Please respecify dimensions of 'constr_sd'.")
    }
    constr_sd[is.na(constr_sd)] <- 0
  }else{
    constr_sd <- matrix(0,horizon,bigK)
  }
  pred_array <- pred.obj$pred_store
  #---------------container---------------------------------------------------------#
  cond_pred <- array(NA, c(thindraws, bigK, horizon))
  dimnames(cond_pred)[[2]] <- varNames
  #----------do conditional forecasting -------------------------------------------#
  if(verbose) cat("Start computing...\n")
  if(verbose) pb <- txtProgressBar(min = 0, max = thindraws, style = 3)
  for(irep in 1:thindraws){
    pred    <- pred_array[irep,,]
    Sigma_u <- Ginv_large[irep,,]%*%S_large[irep,,]%*%t(Ginv_large[irep,,])
    irf     <- .impulsdtrf(B=adrop(F_large[irep,,,,drop=FALSE],drop=1),
                           smat=t(chol(Sigma_u)),nstep=horizon)
    
    temp <- as.vector(constr) + rnorm(bigK*horizon,0,as.vector(constr_sd))
    constr_use <- matrix(temp,horizon,bigK)
    
    v <- sum(!is.na(constr))
    s <- bigK * horizon
    r <- c(rep(0, v))
    R <- matrix(0, v, s)
    pos <- 1
    for(i in 1:horizon) {
      for(j in 1:bigK) {
        if(is.na(constr_use[i, j])) {next}
        r[pos] <- constr_use[i, j] - pred[j, i]
        for(k in 1:i) {
          R[pos, ((k - 1) * bigK + 1):(k * bigK)] <- irf[j,,(i - k + 1)]
        }
        pos <- pos + 1
      }
    }
    
    R_svd <- svd(R, nu=nrow(R), nv=ncol(R))
    U     <- R_svd[["u"]]
    P_inv <- diag(1/R_svd[["d"]])
    V1    <- R_svd[["v"]][,1:v]
    V2    <- R_svd[["v"]][,(v+1):s]
    eta   <- V1 %*% P_inv %*% t(U) %*% r + V2 %*% rnorm(s-v)
    eta   <- matrix(eta, horizon, bigK, byrow=TRUE)
    
    for(h in 1:horizon) {
      temp <- matrix(0, bigK, 1)
      for(k in 1:h) {
        temp <- temp + irf[, , (h - k + 1)] %*% t(eta[k , , drop=FALSE])
      }
      cond_pred[irep,,h] <- pred[,h,drop=FALSE] + temp
    }
    if(verbose) setTxtProgressBar(pb, irep)
  }
  #------------compute posteriors----------------------------------------------#
  imp_posterior<-array(NA,dim=c(bigK,horizon,5))
  dimnames(imp_posterior)[[1]] <- varNames
  dimnames(imp_posterior)[[2]] <- 1:horizon
  dimnames(imp_posterior)[[3]] <- c("low25","low16","median","high75","high84")
  
  imp_posterior[,,"low25"]  <- apply(cond_pred,c(2,3),quantile,0.25,na.rm=TRUE)
  imp_posterior[,,"low16"]  <- apply(cond_pred,c(2,3),quantile,0.16,na.rm=TRUE)
  imp_posterior[,,"median"] <- apply(cond_pred,c(2,3),quantile,0.50,na.rm=TRUE)
  imp_posterior[,,"high75"] <- apply(cond_pred,c(2,3),quantile,0.75,na.rm=TRUE)
  imp_posterior[,,"high84"] <- apply(cond_pred,c(2,3),quantile,0.84,na.rm=TRUE)
  
  #----------------------------------------------------------------------------------#
  out <- structure(list(fcast=imp_posterior,
                        xglobal=xglobal,
                        n.ahead=horizon),
                   class="bgvar.pred")
  if(verbose) cat(paste("\n\nSize of object:", format(object.size(out),unit="MB")))
  end.cond <- Sys.time()
  diff.cond <- difftime(end.cond,start.cond,units="mins")
  mins.cond <- round(diff.cond,0); secs.cond <- round((diff.cond-floor(diff.cond))*60,0)
  if(verbose) cat(paste("\nNeeded time for computation: ",mins.cond," ",ifelse(mins.cond==1,"min","mins")," ",secs.cond, " ",ifelse(secs.cond==1,"second.","seconds.\n"),sep=""))
  return(out)
}

#' @export
"lps" <- function(object){
  UseMethod("lps", object)
}

#' @name lps
#' @title Compute Log-predictive Scores
#' @method lps bgvar.pred
#' @description  Computes and prints log-predictive score of an object of class \code{bgvar.predict}.
#' @param object an object of class \code{bgvar.predict}.
#' @param ... additional arguments.
#' @return Returns an object of class \code{bgvar.lps}, which is a matrix of dimension h times K, whereas h is the forecasting horizon and K is the number of variables in the system.
#' @examples 
#' library(BGVAR)
#' data(eerDatasmall)
#' model.ssvs.eer<-bgvar(Data=eerDatasmall,W=W.trade0012.small,draws=100,burnin=100,
#'                       plag=1,prior="SSVS",eigen=TRUE,h=8)
#' fcast <- predict(model.ssvs.eer,n.ahead=8,save.store=TRUE)
#' lps <- lps(fcast)
#' @author Maximilian Boeck, Martin Feldkircher
#' @importFrom stats dnorm
#' @export
lps.bgvar.pred <- function(object, ...){
  hold.out <- object$hold.out
  h        <- nrow(hold.out)
  K        <- ncol(hold.out)
  if(is.null(hold.out)){
    stop("Please submit a forecast object that includes a hold out sample for evaluation (set h>0 when estimating the model with bgvar)!")
  }
  lps.stats  <- object$lps.stats
  lps.scores <- matrix(NA,h,K)
  for(i in 1:K){
    lps.scores[,i]<-dnorm(hold.out[,i],mean=lps.stats[i,"mean",],sd=lps.stats[i,"sd",],log=TRUE)
  }
  colnames(lps.scores)<-dimnames(lps.stats)[[1]]
  out <- structure(lps.scores, class="bgvar.lps")
  return(out)
}

#' @export
"rmse" <- function(object){
  UseMethod("rmse", object)
}

#' @name rmse
#' @title Compute Root Mean Squared Errors
#' @method rmse bgvar.pred
#' @description  Computes and prints root mean squared errors (RMSEs) of an object of class \code{bgvar.predict}.
#' @param object an object of class \code{bgvar.predict}.
#' @param ... additional arguments.
#' @return Returns an object of class \code{bgvar.rmse}, which is a matrix of dimension h times K, whereas h is the forecasting horizon and K is the number of variables in the system.
#' @examples
#' library(BGVAR)
#' data(eerDatasmall)
#' model.ssvs.eer<-bgvar(Data=eerDatasmall,W=W.trade0012.small,draws=100,burnin=100,
#'                       plag=1,prior="SSVS",eigen=TRUE,h=8)
#' fcast <- predict(model.ssvs.eer,n.ahead=8,save.store=TRUE)
#' rmse <- rmse(fcast)
#' @author Maximilian Boeck, Martin Feldkircher
#' @importFrom knitr kable
#' @importFrom stats dnorm
#' @export
rmse.bgvar.pred <- function(object, ...){
  hold.out <- object$hold.out
  h        <- nrow(hold.out)
  K        <- ncol(hold.out)
  if(is.null(hold.out)){
    stop("Please submit a forecast object that includes a hold out sample for evaluation (set h>0 in fcast)!")
  }
  lps.stats   <- object$lps.stats
  rmse.scores <- matrix(NA,h,K)
  for(i in 1:K){
    rmse.scores[,i]<-sqrt((hold.out[,i]-lps.stats[i,"mean",])^2)
  }
  colnames(rmse.scores)<-dimnames(lps.stats)[[1]]
  out <- structure(rmse.scores, class="bgvar.rmse")
  return(out)
}

#' @method print bgvar.lps
#' @export
#' @importFrom knitr kable
print.bgvar.lps<-function(x, ...){
  h    <- dim(x)[1]
  cN   <- unique(sapply(strsplit(colnames(x),".",fixed=TRUE),function(y)y[1]))
  vars <- unique(sapply(strsplit(colnames(x),".",fixed=TRUE),function(y)y[2]))
  cntry <- round(sapply(cN,function(y)mean(x[grepl(y,colnames(x))])),2)
  K     <- ceiling(length(cntry)/10)
  mat.c <- matrix(NA,nrow=2*K,ncol=10)
  for(i in 1:K){
    if(i<K) {
      mat.c[(i-1)*2+1,] <- names(cntry)[((i-1)*10+1):(i*10)]
      mat.c[(i-1)*2+2,] <- as.numeric(cntry)[((i-1)*10+1):(i*10)]
    }else{
      mat.c[(i-1)*2+1,1:(length(cntry)-(i-1)*10)] <- names(cntry)[((i-1)*10+1):length(cntry)]
      mat.c[(i-1)*2+2,1:(length(cntry)-(i-1)*10)] <- as.numeric(cntry)[((i-1)*10+1):length(cntry)]
    }
  }
  mat.c[is.na(mat.c)] <- ""
  colnames(mat.c) <- rep("",10)
  vars  <- round(sapply(vars,function(y)mean(x[grepl(y,colnames(x))])),2)
  K     <- ceiling(length(vars)/10)
  mat.v <- matrix(NA,nrow=2*K,ncol=10)
  for(i in 1:K){
    if(i<K) {
      mat.v[(i-1)*2+1,] <- names(vars)[((i-1)*10+1):(i*10)]
      mat.v[(i-1)*2+2,] <- as.numeric(vars)[((i-1)*10+1):(i*10)]
    }else{
      mat.v[(i-1)*2+1,1:(length(vars)-(i-1)*10)] <- names(vars)[((i-1)*10+1):length(vars)]
      mat.v[(i-1)*2+2,1:(length(vars)-(i-1)*10)] <- as.numeric(vars)[((i-1)*10+1):length(vars)]
    }
  }
  mat.v[is.na(mat.v)] <- ""
  colnames(mat.v) <- rep("",10)
  K     <- ceiling(h/10)
  mat.h <- matrix(NA,nrow=2*K,ncol=10)
  for(i in 1:K){
    if(i<K) {
      mat.h[(i-1)*2+1,] <- paste("h=",seq(((i-1)*10+1),(i*10),by=1),sep="")
      mat.h[(i-1)*2+2,] <- round(rowSums(x[((i-1)*10+1):(i*10),]),2)
    }else{
      mat.h[(i-1)*2+1,1:(h-(i-1)*10)] <- paste("h=",seq(((i-1)*10+1),h,by=1),sep="")
      mat.h[(i-1)*2+2,1:(h-(i-1)*10)] <- round(rowSums(x[((i-1)*10+1):h,]),2)
    }
  }
  mat.h[is.na(mat.h)] <- ""
  colnames(mat.h) <- rep("",10)
  
  cat("---------------------------------------------------------------------------")
  cat("\n")
  cat("Log-predictive scores per country")
  cat(kable(mat.c), "rst")
  cat("\n")
  cat("---------------------------------------------------------------------------")
  cat("\n")
  cat("Log-predictive scores per variable")
  cat(kable(mat.v), "rst")
  cat("\n")
  cat("---------------------------------------------------------------------------")
  cat("\n")
  cat("Log-predictive scores per horizon")
  cat(kable(mat.h), "rst")
  cat("\n")
  cat("---------------------------------------------------------------------------")
}

#' @method print bgvar.rmse
#' @export
#' @importFrom knitr kable
print.bgvar.rmse<-function(x, ...){
  h    <- dim(x)[1]
  cN   <- unique(sapply(strsplit(colnames(x),".",fixed=TRUE),function(y)y[1]))
  vars <- unique(sapply(strsplit(colnames(x),".",fixed=TRUE),function(y)y[2]))
  cntry <- round(sapply(cN,function(y)mean(x[grepl(y,colnames(x))])),2)
  K     <- ceiling(length(cntry)/10)
  mat.c <- matrix(NA,nrow=2*K,ncol=10)
  for(i in 1:K){
    if(i<K) {
      mat.c[(i-1)*2+1,] <- names(cntry)[((i-1)*10+1):(i*10)]
      mat.c[(i-1)*2+2,] <- as.numeric(cntry)[((i-1)*10+1):(i*10)]
    }else{
      mat.c[(i-1)*2+1,1:(length(cntry)-(i-1)*10)] <- names(cntry)[((i-1)*10+1):length(cntry)]
      mat.c[(i-1)*2+2,1:(length(cntry)-(i-1)*10)] <- as.numeric(cntry)[((i-1)*10+1):length(cntry)]
    }
  }
  mat.c[is.na(mat.c)] <- ""
  colnames(mat.c) <- rep("",10)
  vars  <- round(sapply(vars,function(y)mean(x[grepl(y,colnames(x))])),2)
  K     <- ceiling(length(vars)/10)
  mat.v <- matrix(NA,nrow=2*K,ncol=10)
  for(i in 1:K){
    if(i<K) {
      mat.v[(i-1)*2+1,] <- names(vars)[((i-1)*10+1):(i*10)]
      mat.v[(i-1)*2+2,] <- as.numeric(vars)[((i-1)*10+1):(i*10)]
    }else{
      mat.v[(i-1)*2+1,1:(length(vars)-(i-1)*10)] <- names(vars)[((i-1)*10+1):length(vars)]
      mat.v[(i-1)*2+2,1:(length(vars)-(i-1)*10)] <- as.numeric(vars)[((i-1)*10+1):length(vars)]
    }
  }
  mat.v[is.na(mat.v)] <- ""
  colnames(mat.v) <- rep("",10)
  K     <- ceiling(h/10)
  mat.h <- matrix(NA,nrow=2*K,ncol=10)
  for(i in 1:K){
    if(i<K) {
      mat.h[(i-1)*2+1,] <- paste("h=",seq(((i-1)*10+1),(i*10),by=1),sep="")
      mat.h[(i-1)*2+2,] <- round(rowSums(x[((i-1)*10+1):(i*10),]),2)
    }else{
      mat.h[(i-1)*2+1,1:(h-(i-1)*10)] <- paste("h=",seq(((i-1)*10+1),h,by=1),sep="")
      mat.h[(i-1)*2+2,1:(h-(i-1)*10)] <- round(rowSums(x[((i-1)*10+1):h,]),2)
    }
  }
  mat.h[is.na(mat.h)] <- ""
  colnames(mat.h) <- rep("",10)
  
  cat("---------------------------------------------------------------------------")
  cat("\n")
  cat("Root-mean squared error per country")
  cat(kable(mat.c), "rst")
  cat("\n")
  cat("---------------------------------------------------------------------------")
  cat("\n")
  cat("Root-mean squared error per variable")
  cat(kable(mat.v), "rst")
  cat("\n")
  cat("---------------------------------------------------------------------------")
  cat("\n")
  cat("Root-mean squared error per horizon")
  cat(kable(mat.h), "rst")
  cat("\n")
  cat("---------------------------------------------------------------------------")
}
