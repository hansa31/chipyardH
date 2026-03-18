## Plan: CIFAR-10 MobileNetV2 for Gemmini

Adapt the existing MobileNetV2 for CIFAR-10 (10 classes, native 32x32 input). Create 2 Python weight extraction scripts (float + int8), 2 C inference files, and a CIFAR-10 images header. Use `jialicheng/cifar10_mobilenet-v2` from HuggingFace (fine-tuned from our exact base model, same state dict structure, 10-class output).

**Key insight**: Weight array shapes are **identical** regardless of input image size — only buffer sizes and spatial params change. The backbone (conv_1–conv_52) can be reused directly for 32x32 input.

### Spatial dimension map (32x32 input, batch_size=4)

| ImageNet | CIFAR-10 | n_patches (ImageNet → CIFAR-10) | Layers |
|---|---|---|---|
| 112×112 | 16×16 | 50176 → **1024** | conv_1, conv_dw_2, conv_3, conv_4 |
| 56×56 | 8×8 | 12544 → **256** | conv_dw_5..conv_10 |
| 28×28 | 4×4 | 3136 → **64** | conv_dw_11..conv_19 |
| 14×14 | 2×2 | 784 → **16** | conv_dw_20..conv_40 |
| 7×7 | 1×1 | 196 → **4** | conv_dw_41..conv_52 |

FC: 1000 → **10** classes. Buffers shrink enormously.

---

### Steps

**Phase 1: Python Scripts** (in `imagenet/float_weights/`)

1. **Create `extract_mobilenet_cifar10_float.py`** — Load `jialicheng/cifar10_mobilenet-v2` (same HuggingFace Transformers architecture as our base). Reuse `build_layer_mapping()`, `fold_bn()`, reshape functions from existing `extract_mobilenet_weights.py`. Recompute `CONV_PARAMS` with CIFAR-10 spatial dims (only `in_row_dim`, `in_col_dim`, `out_row_dim`, `out_col_dim`, `n_patches`, `I`, `out_dim_pooled` change; weights/channels/kernel unchanged). FC: 10 classes, `output_scale=1.0f`. Output: `mobilenet_cifar10_params_float.h`

2. **Create `extract_mobilenet_cifar10_int.py`** — *parallel with step 1*. Same extraction + per-layer min-max INT8 quantization: `scale = max(|w|)/127`, `w_int8 = clip(round(w/scale), -128, 127)`. Biases quantized to int32. Compute power-of-2 `output_scale` values per layer based on weight magnitudes and estimated activation ranges from BN running stats. Output: `mobilenet_cifar10_params.h`

3. **Generate `cifar10_images.h`** from both scripts — Download CIFAR-10 test set via `torchvision.datasets.CIFAR10`, pick 4 images with known labels. Apply MobileNetV2 normalization, quantize appropriately (int8 or float). Output: `static const elem_t images[4][32][32][3] row_align(1) = {...};`

**Phase 2: C Files** (in `imagenet/`)

4. **Create `mobilenet_cifar10.c`** — *parallel with steps 1-3*. Copy `mobilenet.c` changing only 3 lines: `#include "mobilenet_cifar10_params.h"`, `#include "cifar10_images.h"`, and `correct[]` array (CIFAR-10 labels 0-9). Everything else works as-is — all layer calls read dimensions from params structs, `average[1280][4]` stays same, prediction loop uses `fc_53_params.out_features` (= 10).

5. **Create `mobilenet_cifar10_float.c`** — *parallel with step 4*. Same as above but `#include "mobilenet_cifar10_params_float.h"`.

### Relevant files

- `imagenet/float_weights/extract_mobilenet_weights.py` — template script, reuse `build_layer_mapping()`, `fold_bn()`, `reshape_conv_weight()`, `reshape_dw_weight()`, `fmt_*()`, `write_*()` functions
- `imagenet/mobilenet.c` — base C file, copy with 3-line change
- `imagenet/mobilenet_params.h` — reference for struct formatting and field names

### Verification

1. Run both Python scripts — check 53-layer extraction succeeds and shapes validate
2. Verify `conv_1_params` has `in_row_dim=32, out_row_dim=16, n_patches=1024, I=1024`
3. Verify `fc_53_params` has `out_features=10, I=10`
4. Verify `conv_1_in[1024][27]`, `conv_1_out[1024][32]` buffer sizes
5. Verify `cifar10_images.h` has `images[4][32][32][3]`
6. Diff `mobilenet_cifar10.c` vs `mobilenet.c` — should differ only in includes + `correct[]`

### Decisions

- **Native 32×32** input (not upscaled to 224×224). Buffers are much smaller. Accuracy will be lower than reported 84.46% (which was trained at 224x224).
- **`jialicheng/cifar10_mobilenet-v2`** for pretrained weights (10-class FC head, same architecture).
- **Per-layer min-max** INT8 quantization. Power-of-2 output_scale values.
- **Existing code untouched** — `mobilenet.c` and `mobilenet_params.h` are not modified.
- **CIFAR-10 images** generated as part of the script output.

### Further Considerations

1. **Modified first-layer stride**: Many CIFAR-10 papers change conv_1 stride from 2→1 to preserve spatial resolution at 32x32. Would give richer features but changes all downstream dims. **Recommendation**: keep as-is for now, revisit if accuracy is insufficient.
2. **Fine-tuning**: For best accuracy at native 32x32, the model should be re-fine-tuned with 32x32 input. The generated headers provide the correct structure for that workflow.

Please have the models made so that we can have the best accuracy, and the check whether there is any INT8 quantized model as well
