# This is the script to represent data with basis functions
# Available basis: B-Spline and temporal basis function through SVD
rm(list = ls())
source("./src/database.R")
source("config.R")
source("./src/plot.R")
source("./src/spatialHelper.R")
source("./src/interpolation.R")

require(fda)
require(sp)
require(gstat)
require(dplyr)
require(reshape2)
require(geoR)


coeff2Value <- function(coef, basis){
	# coef is a vector
	# basis a a vector
	return(basis %*% t(coef)) # return a matrix
}


plot_variogram <- function(df, formu = "value~1"){
	coordinates(df) = ~x+y
	print(plot(variogram(as.formula(formu),data =df,cutoff = 120, cloud=TRUE)))
}

basis_interpolation <- function(DOdata, logger_geo, grid, timeIndex = NULL, basis = "fda",...){
	# DOdata is the dataframe
	# basis can take "fda" or "svd"
	# time index is a vector that specify how long data is used
	args <- list(...)
	ID <- as.numeric(colnames(DOdata))
	T <- nrow(DOdata)  # Totally how many timestamps

	if(basis == "fda"){
		decompRes <- B_spline(DOdata.args$knots)
	}else{
		decompRes <- SVD_basis(DOdata,args$r)
		nBasis <- dim(decompRes$coef)[1] # columns of the coefficent matrix
	}

	basis <- decompRes$basis

	# construct complete coefficient matrix
	coef <- decompRes$coef %>% t() %>% as.data.frame()
	coef$ID <- ID
	coef_df <- merge(coef,logger_geo,by.x = "ID",by.y = "loggerID")
	
	# do interpolation on each basis coefficients
	prediction <- matrix(0,T,nrow(grid)) # a matrix T * nBasis, row is time, columns is locations

	for(i in 1:nBasis){
		spData <- coef_df[,c("x","y",paste("V",i,sep = ""),"bathymetry","longitude","latitude")]
		names(spData)[3] <- "value"
		plot_variogram(spData)
		pred <- spatial_interpolation(spData,grid,"loglik") # res is a vector of interpolated coefficient of basis i
		prediction <- prediction + basis[,i] %*% t(pred) # project the coefficients to values
	}

	# do interpolation on the residuals
	DO_res <- DOdata - decompRes$fit  # a matrix of shape T*nLocation
	

	return(list(trend = prediction,res = DO_res))
}


SVD_basis <- function(DOdata, r){
	DOdata <- as.matrix(DOdata)
	svdRes <- svd(DOdata)

	coef <- (diag(svdRes$d) %*% t(svdRes$v))[1:r,]
	basis <- svdRes$u[,1:r]

	DO_fit <- basis %*% coef # coef, each column is the coefficents for different basis

	return(list(fit = DO_fit, coef = coef, basis = basis))

}


B_spline <- function(DOdata,knots,norder = 4){
	
	T <- nrow(DOdata)
	DOdata <- as.matrix(DOdata)
	nBasis <- length(knots)-2+norder
	bbasis <- create.bspline.basis(range(knots),nBasis,norder,knots)

	basismat <- eval.basis(1:T, bbasis)
	coef <- solve(crossprod(basismat), crossprod(basismat,DOdata))
	
	DOfd <- fd(coef, bbasis)
	DO_fit <- predict(DOfd,1:T)

	return(list(fit = DO_fit, coef = coef, basis = bbasis))  # return fit value, coefficients and basis object
}	






# B_spline <- function(DOdata,logger_geo,timeIndex, norder = 4){
# 	# DOdata is a dataframe, each column is a series of data from one sensor
# 	DOdata <- DOdata[1:104,] %>% as.matrix()
	
# 	norder <- 4
# 	knots <- seq(0,110,7)
# 	nBasis <- length(knots)-2+norder
# 	bbasis <- create.bspline.basis(c(0,105),nBasis,norder,knots)

# 	basismat <- eval.basis(1:104, bbasis)
# 	coef <- solve(crossprod(basismat), crossprod(basismat,DOdata))
	
# 	DOfd <- fd(coef, bbasis,list("Day", "Year", "DO (mg/L)"))
# 	# plot(DOfd, lty=1, lwd=2, col=1)

# 	DO_fit <- predict(DOfd,1:104)
# 	DO_res <- (DOdata-DO_fit) %>% as.data.frame()


# 	for(i in 1:ncol(DOdata)){
# 	#	plotfit.fd(DOdata[,i], 1:104, DOfd[i], lty=1, lwd=2)
# 	}
	 
# 	coef_t <- t(coef) %>% as.data.frame()
# 	coef_t$ID <- as.numeric(rownames(coef_t))

# 	coef_df <- merge(coef_t,logger_geo,by.x = "ID",by.y = "loggerID")

	
# 	return(list(fit = DO_fit,res = DO_res,coef = coef_df,basis = bbasis))
# }




# test
# debug(fda)
timeRange <- c("2014-06-23","2014-10-05")


year <- 2014
bottomLogger_2014 <- retriveGeoData(year,"B") %>% arrange(loggerID) %>% lonlat2UTM()
data_2014 <- retriveLoggerData(bottomLogger_2014$loggerID,year,"DO","daily","AVG",timeRange = timeRange)
time_2014 <- index(data_2014)
grid <- createGrid(bottomLogger_2014)
trendPrediction <- basis_interpolation(data_2014,bottomLogger_2014,grid,basis = "svd", r = 5)
finalPrediction <- cbind(t(trendPrediction$trend),grid)






# fda_res <- fda(data_2014,bottomLogger_2014,time_2014)


# # spatial analysis on the coefficients
# coef_df <- fda_res[[3]]
# coef_df2 <- coef_df
# coordinates(coef_df2) = ~x+y
# bbasis <- fda_res[[4]]

# for(i in 1:18){
# 	formu <- as.formula(sprintf("bspl4.%d~1",i))
# 	print(plot(variogram(formu,data =coef_df2,cutoff = 120)))
# }

# loci <- createGrid(bottomLogger_2014) %>% lonlat2UTM()


# krigingCoeff <- matrix(0,nrow(loci),18)

# for(i in 1:18){
# 	subDF <- coef_df[,c("x","y",paste("bspl4.",i,sep = ""),"ID")] %>% as.geodata()
# 	ml <- likfit(subDF, ini = c(1,0.5), fix.nugget = T, method = "RML") # using loglikelihood to estimate
# 	krigingCoeff[,i] <- krige.conv(subDF, locations = loci[,c("x","y")], krige = krige.control(obj.m = ml))$predict
	
# 	# reconstruct
# 	# plot 
# 	# bin1 <- variog(subDF)
# 	# plot(bin1, main = expression(paste("fixed ")))
# 	# lines(ml)
# }

# # construct 
# fdobj <- fd(t(krigingCoeff),bbasis)
# allInterpolation <- predict(fdobj,1:104)  # a matrix with 104* nGrid

# allDf <- list()
# for(i in 1:104){
# 	loci$pred <- allInterpolation[i,]
# 	attributes(loci)$time <- i
# 	allDf[[i]] <- subset(loci,convexIndex ==1)
# }

# plot_spatial(allDf,bottomLogger_2014,"./output/newRes")


# # bayesian kriging
# MC <- model.control(cov.model = "exponential")  # model control
# PC <- prior.control(phi.discrete=seq(30,100,5)) # priors

# OC <- output.control(n.pos = 500, n.pred = 100, quantile = c(0.25, 0.5, 0.75), thres = 1.5)
# # n.pos: number of samples to be taken from the posterior distribution
# # n.pred: number of samples to be taken from the predictive distribution
# # 

# s100.kb <- krige.bayes(subDF, loc=loci[1:10,c("x","y")], model=MC, prior=PC, out=OC)

# # # spatial temporal analysis
# # DO_res <- fda_res$res
# # DO_res$logger_time <- as.POSIXct(time_2014)
# # DO_res <- melt(DO_res,id.vars = c("logger_time")) %>% 
# # 	arrange(logger_time,variable) %>%
# # 	rename(ID = variable)

# # coordinates(bottomLogger_2014)=~longitude+latitude
# # raster::projection(bottomLogger_2014)=CRS("+init=epsg:4326")

# # # year <- 2015
# # # bottomLogger_2015 <- retriveGeoData(year,"B")
# # # data_2015 <- retriveLoggerData(bottomLogger_2015$loggerID,year,"DO","daily","AVG",transform=TRUE)

# # timeDF <- STFDF(sp=bottomLogger_2014,time=time_2014,data=data.frame(value = DO_res$value))
# vST <- variogramST(value~longitude+latitude+bathymetry+I(bathymetry^2),timeDF,tlags = 0:10,cutoff = 120)
# plot(vST,map=FALSE)

# fda(DOdata,logger)