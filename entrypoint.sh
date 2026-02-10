#!/bin/bash
set -e

# =============================================================================
# ComfyUI Entrypoint for Strix Halo Docker Container
# Handles first-run directory setup, ComfyUI-Manager seeding, and startup.
# =============================================================================

# ---- Create model subdirectories in mounted volume (if empty) ----------------
MODEL_DIRS=(
    checkpoints clip clip_vision configs controlnet diffusers
    diffusion_models embeddings gligen hypernetworks loras
    style_models text_encoders unet upscale_models vae vae_approx
    audio_encoders model_patches
)

for dir in "${MODEL_DIRS[@]}"; do
    mkdir -p "/app/ComfyUI/models/${dir}"
done

mkdir -p /app/ComfyUI/output
mkdir -p /app/ComfyUI/input
mkdir -p /app/ComfyUI/temp
mkdir -p /app/ComfyUI/user
mkdir -p /app/ComfyUI/custom_nodes

# ---- Seed ComfyUI-Manager into custom_nodes if not present -------------------
# The image ships ComfyUI-Manager in _builtin_custom_nodes/. On first run with
# an empty custom_nodes volume mount, we copy it over so the user gets it by
# default. They can remove it if unwanted.
if [ -d "/app/ComfyUI/_builtin_custom_nodes/ComfyUI-Manager" ] && \
   [ ! -d "/app/ComfyUI/custom_nodes/ComfyUI-Manager" ]; then
    echo "[entrypoint] Seeding ComfyUI-Manager into custom_nodes/..."
    cp -r /app/ComfyUI/_builtin_custom_nodes/ComfyUI-Manager \
          /app/ComfyUI/custom_nodes/ComfyUI-Manager
fi

# ---- Print configuration summary --------------------------------------------
echo "============================================"
echo " ComfyUI for AMD Strix Halo (gfx1151)"
echo "============================================"
echo " HSA_OVERRIDE_GFX_VERSION : ${HSA_OVERRIDE_GFX_VERSION:-not set}"
echo " HSA_ENABLE_SDMA          : ${HSA_ENABLE_SDMA:-not set}"
echo " GPU_MAX_ALLOC_PERCENT    : ${GPU_MAX_ALLOC_PERCENT:-not set}"
echo " GPU_MAX_HEAP_SIZE        : ${GPU_MAX_HEAP_SIZE:-not set}"
echo " HIP_VISIBLE_DEVICES      : ${HIP_VISIBLE_DEVICES:-not set}"
echo " FLASH_ATTENTION_TRITON   : ${FLASH_ATTENTION_TRITON_AMD_ENABLE:-not set}"
echo " PYTORCH_HIP_ALLOC_CONF   : ${PYTORCH_HIP_ALLOC_CONF:-not set}"
echo "============================================"
echo ""

# ---- Verify ROCm can see the GPU --------------------------------------------
if command -v rocm-smi &> /dev/null; then
    echo "[entrypoint] ROCm GPU status:"
    rocm-smi --showproductname 2>/dev/null || echo "  (rocm-smi query failed - GPU may still work)"
    echo ""
elif command -v rocminfo &> /dev/null; then
    echo "[entrypoint] ROCm agents detected:"
    rocminfo 2>/dev/null | grep -E "Marketing Name|Name:" | head -6 || true
    echo ""
fi

# ---- Quick PyTorch ROCm sanity check -----------------------------------------
python3 -c "
import torch
print(f'[entrypoint] PyTorch {torch.__version__}')
print(f'[entrypoint] ROCm available: {torch.cuda.is_available()}')
if torch.cuda.is_available():
    print(f'[entrypoint] GPU: {torch.cuda.get_device_name(0)}')
    mem_gb = torch.cuda.get_device_properties(0).total_memory / (1024**3)
    print(f'[entrypoint] GPU memory: {mem_gb:.1f} GB')
" 2>/dev/null || echo "[entrypoint] Warning: PyTorch GPU check failed"

echo ""
echo "[entrypoint] Starting ComfyUI on 0.0.0.0:8188 ..."
echo ""

# ---- Launch ComfyUI ----------------------------------------------------------
exec python3 main.py \
    --listen 0.0.0.0 \
    --port 8188 \
    --preview-method auto \
    ${COMFYUI_EXTRA_ARGS}
