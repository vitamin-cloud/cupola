FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg libsndfile1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY alicevoice/ alicevoice/
RUN printf '#!/bin/sh\nexec python -m alicevoice "$@"\n' > /usr/local/bin/av \
 && chmod +x /usr/local/bin/av

ENV PYTHONUNBUFFERED=1
