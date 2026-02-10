# =============================================================================
# ComfyUI Docker Image for AMD Ryzen AI Max Pro 390 (Strix Halo / gfx1151)
#
# GPU:  Radeon 8060S iGPU - 40 CUs, RDNA 3.5, ~59 TFLOPS FP16
# ROCm: Uses gfx1100 compatibility mode via HSA_OVERRIDE_GFX_VERSION
#       (currently 2-6x faster than native gfx1151 kernels in many workloads)
#
# Runs on:
#   - Windows 10/11 via WSL2 + Docker Desktop (primary target)
#   - Native Linux with docker-compose.linux.yml override
#
# Build:
#   docker compose build
#   docker build -t comfyui-strix-halo .
#
# Alternative base images (pass via --build-arg BASE_IMAGE=...):
#   rocm/pytorch:rocm6.2_ubuntu22.04_py3.10_pytorch_release_2.3.0
#   rocm/pytorch:rocm6.4.2_ubuntu24.04_py3.12_pytorch_release_2.6.0
# =============================================================================

ARG BASE_IMAGE=rocm/pytorch:latest
FROM ${BASE_IMAGE}

LABEL maintainer="DockerComfy_StrixHalo"
LABEL description="ComfyUI optimized for AMD Ryzen AI Max Pro 390 (Strix Halo)"

ENV DEBIAN_FRONTEND=noninteractive

# ---- System dependencies ----------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    curl \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    && rm -rf /var/lib/apt/lists/*

# ---- Strix Halo (gfx1151) environment variables -----------------------------
# Route GPU compute through gfx1100 kernels (faster than native gfx1151 today)
ENV HSA_OVERRIDE_GFX_VERSION=11.0.0
# Prevent checkerboard artifacts during VAE decode on APUs
ENV HSA_ENABLE_SDMA=0
# Allow full unified memory allocation (APU shares system RAM with GPU)
ENV GPU_MAX_ALLOC_PERCENT=100
ENV GPU_MAX_HEAP_SIZE=100
# Target the integrated GPU
ENV HIP_VISIBLE_DEVICES=0
# PyTorch memory allocator tuning for unified memory architecture
ENV PYTORCH_HIP_ALLOC_CONF="backend:native,expandable_segments:True,garbage_collection_threshold:0.9,max_split_size_mb:512"
# Use Triton-backed flash attention (native flash-attn lacks gfx1151 support)
ENV FLASH_ATTENTION_TRITON_AMD_ENABLE=1
# Enable experimental AOTriton attention kernels
ENV TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1

# ---- Install/upgrade PyTorch ROCm -------------------------------------------
# The base image has PyTorch, but we ensure the ROCm 6.2 wheels are installed
# (most stable for gfx1151 via HSA override). Skip if the base already matches.
ARG PYTORCH_ROCM_INDEX=https://download.pytorch.org/whl/rocm6.2
ARG SKIP_PYTORCH_INSTALL=false
RUN if [ "$SKIP_PYTORCH_INSTALL" = "false" ]; then \
    pip3 install --no-cache-dir --break-system-packages \
        torch torchvision torchaudio \
        --index-url ${PYTORCH_ROCM_INDEX}; \
    fi

# ---- Clone ComfyUI ----------------------------------------------------------
ARG COMFYUI_REF=master
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI && \
    cd /app/ComfyUI && \
    git checkout ${COMFYUI_REF}

WORKDIR /app/ComfyUI

# ---- Install ComfyUI Python dependencies ------------------------------------
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# ---- Install ComfyUI-Manager (optional, built into image) -------------------
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git \
    /app/ComfyUI/_builtin_custom_nodes/ComfyUI-Manager

# ---- Create default directories for volume mounts ---------------------------
RUN mkdir -p \
    models/checkpoints \
    models/clip \
    models/clip_vision \
    models/configs \
    models/controlnet \
    models/diffusers \
    models/diffusion_models \
    models/embeddings \
    models/gligen \
    models/hypernetworks \
    models/loras \
    models/style_models \
    models/text_encoders \
    models/unet \
    models/upscale_models \
    models/vae \
    models/vae_approx \
    models/audio_encoders \
    models/model_patches \
    output \
    input \
    temp \
    user \
    custom_nodes

# ---- Entrypoint --------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8188

ENTRYPOINT ["/entrypoint.sh"]
