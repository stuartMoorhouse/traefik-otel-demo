FROM --platform=$BUILDPLATFORM cgr.dev/chainguard/python:latest-dev@sha256:71441d06293ef128d9be3b1522186e87773f41fab82a09ed791207daad34281d AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM cgr.dev/chainguard/python:latest@sha256:bd849aeb63c12208ea68faa568c3874737cdc4d3742619d27e33bfb980c5772c

WORKDIR /app

COPY --from=builder /home/nonroot/.local /home/nonroot/.local
COPY app.py .

ENV PATH="/home/nonroot/.local/bin:$PATH"
EXPOSE 5000

USER nonroot
ENTRYPOINT ["opentelemetry-instrument"]
CMD ["python", "app.py"]
