FROM ghcr.io/bimberlabinternal/cellmembrane:latest

ADD . /RIRA_classification

ENV RETICULATE_PYTHON=/usr/bin/python3

RUN pip3 install celltypist

RUN cd /RIRA_classification \
	&& R CMD build . \
	&& Rscript -e "BiocManager::install(ask = F, upgrade = 'always');" \
	&& Rscript -e "devtools::install_deps(pkg = '.', dependencies = TRUE, upgrade = 'always');" \
	&& R CMD INSTALL --build *.tar.gz \
	&& rm -Rf /tmp/downloaded_packages/ /tmp/*.rds
