FROM cgr.dev/chainguard/python:latest-dev@sha256:47e96d249309a713577a64f20374d3d2741a8186d0f9db30d92f32b14f1ab803 AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM cgr.dev/chainguard/python:latest@sha256:0211d3c85dc066113ebfc14b977fba957f546c94f7d984ec906d87fd3c498ba6

WORKDIR /app

COPY --from=builder /home/nonroot/.local /home/nonroot/.local
COPY app.py .

ENV PATH="/home/nonroot/.local/bin:$PATH"
EXPOSE 5000

USER nonroot
ENTRYPOINT ["opentelemetry-instrument"]
CMD ["python", "app.py"]
