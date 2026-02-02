FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python tools
RUN pip install --no-cache-dir \
    yt-dlp \
    openai-whisper

# Create working directory
WORKDIR /work

# Keep container running
CMD ["tail", "-f", "/dev/null"]
