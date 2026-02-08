FROM minio/mc AS mc

FROM python:3.11-slim
COPY --from=mc /usr/bin/mc /usr/local/bin/mc
RUN pip install --no-cache-dir huggingface_hub
