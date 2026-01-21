ARG BASE_IMAGE=ghcr.io/rocker-org/shiny:4.3.3
ARG BASE_PLATFORM=linux/amd64
FROM --platform=${BASE_PLATFORM} ${BASE_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends emboss python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages('jsonlite', repos='https://cloud.r-project.org')"

WORKDIR /app
COPY . /app

EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/app/primersearch_gui', host='0.0.0.0', port=3838)"]
