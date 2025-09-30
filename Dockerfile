FROM alpine:3 as downloader

WORKDIR /work

COPY latest_version.txt latest_version.txt

RUN apk add --no-cache curl && \
    arch=$(uname -m | sed s/aarch64/arm64/ | sed s/x86_64/amd64/) && \
    version=$(cat latest_version.txt) && \
    curl -L -S -s -o sysdig-cli-scanner "https://download.sysdig.com/scanning/bin/sysdig-cli-scanner/$version/linux/$arch/sysdig-cli-scanner" && \
    sha256sum -c <(curl -sL "https://download.sysdig.com/scanning/bin/sysdig-cli-scanner/$version/linux/$arch/sysdig-cli-scanner.sha256") && \
    chmod +x sysdig-cli-scanner

FROM alpine/helm:3 as helm

WORKDIR /work

RUN helm repo add sysdig https://charts.sysdig.com && helm repo update
RUN helm pull sysdig/registry-scanner && helm pull sysdig/shield

FROM alpine:3

WORKDIR /scanner

RUN apk add --no-cache tini && \
    mkdir -p /cache && \
    mkdir -p /helm-assets && \
    adduser -D -h /scanner scanuser && \
    chown -R scanuser:scanuser /cache /scanner /helm-assets

USER scanuser

COPY entrypoint.sh /entrypoint.sh
COPY --chown=scanuser:scanuser --from=downloader /work/sysdig-cli-scanner /scanner/sysdig-cli-scanner
COPY --chown=scanuser:scanuser --from=helm /work/ /helm-assets/

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

CMD [ "--apiurl", "${SYSDIG_SECURE_ENDPOINT}", "--console-log", "--dbpath=/cache/db/", "--cachepath=/cache/scanner-cache/", "${OPTIONS:- --skipupload --full-vulns-table --detailed-policies-eval}", "${IMAGE_NAME}" ]
