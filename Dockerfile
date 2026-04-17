FROM --platform=$BUILDPLATFORM cgr.dev/chainguard/python:3.12-dev AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM cgr.dev/chainguard/python:3.12

WORKDIR /app

COPY --from=builder /home/nonroot/.local /home/nonroot/.local
COPY app.py .

ENV PATH="/home/nonroot/.local/bin:$PATH"
EXPOSE 5000

USER nonroot
ENTRYPOINT ["opentelemetry-instrument"]
CMD ["python", "app.py"]
