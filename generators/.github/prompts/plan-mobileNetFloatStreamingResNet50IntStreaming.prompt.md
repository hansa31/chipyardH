# Plan: MobileNet Float Streaming + ResNet50 INT8 Streaming

Create two new C inference files and update the Makefile. Both use INT8 images from `.bin`. Keep `elem_t`/`acc_t` unchanged. No original files modified.

---

**Steps**

### Phase A: `mobilenet_v1_float.c`
1. Create `imagenet/mobilenet_v1_float.c` — copy of `mobilenet_v1.c` with `#include "mobilenet_params_float.h"` instead of `mobilenet_params.h`. Everything else identical: streaming via `fread`, A/B test with `images.h`, top-K accuracy, window reporting. The float header has `output_scale=1.0f` for all layers, which is the only functional difference.

### Phase B: `resnet50_v1.c`
2. Create `imagenet/resnet50_v1.c` — streaming ResNet50 using `resnet50_params.h` (INT8). Outer shell from `mobilenet_v1.c` (streaming, labels, accuracy), network body from `resnet50.c` (53 conv + `tiled_global_average_auto` + fc_54). Key architectural differences from MobileNet streaming:
   - **conv_1** has max pooling (`pool_size=3, pool_stride=2`) → `conv_1_out_pooled` buffer
   - **No depthwise convs** — all 3×3 are `tiled_conv_auto` or `im2col_with_col2im`
   - **Downsample shortcuts**: conv_5 (matmul), conv_15 (`tiled_conv_downsample`), conv_28 (`tiled_conv_downsample`), conv_47 (`tiled_conv_auto`)
   - **Residual adds** with `true` (ReLU after) at end of each bottleneck block
   - **Global averaging**: `tiled_global_average_auto()` → `average[4][2048]`
   - **FC layout**: `fc_54_out[batch][class]` (transposed vs MobileNet's `fc_53_out[class][batch]`)
   - Prediction loop iterates `fc_54_out[batch][i]` for each batch

### Phase C: Makefile
3. Add `mobilenet_v1_float` and `resnet50_v1` to the `tests` list in `imagenet/Makefile`

---

**Relevant files**
- `imagenet/mobilenet_v1.c` — template for streaming infrastructure
- `imagenet/mobilenet_float.c` — reference for float MobileNet layer calls
- `imagenet/resnet50.c` — template for ResNet50 network body (53 conv + tiled_global_average_auto + fc_54)
- `imagenet/resnet50_params.h` — INT8 ResNet50 weights
- `imagenet/Makefile` — add new build targets

**Verification**
1. `make -C imagenet mobilenet_v1_float-linux` and `make -C imagenet resnet50_v1-linux` compile without errors
2. `mobilenet_v1_float.c` includes `mobilenet_params_float.h`, identical streaming to `mobilenet_v1.c`
3. `resnet50_v1.c` includes `resnet50_params.h`, network body matches `resnet50.c` exactly, wrapped in streaming loop
4. Both use `elem_t`/`acc_t` throughout — no raw `float` or `int8_t`
5. `resnet50_v1.c` uses `fc_54_out[batch][class]` layout for predictions (not MobileNet's transposed layout)
6. `resnet50_v1.c` uses `tiled_global_average_auto` (not manual averaging loop)
7. No original files modified

**Decisions**
- Scope: only `mobilenet_v1_float.c`, `resnet50_v1.c`, Makefile (per user selection)
- `extract_resnet50_weights.py` and `resnet50_float.c` excluded from this round
- All inputs are INT8 images from the same `.bin` file

**Further Considerations**
1. The ResNet50 expected labels for images.h are `{75, 900, 641, 897}` (differs from MobileNet's `{75, 900, 125, 897}`) — the A/B test in `resnet50_v1.c` should use the ResNet50 expected values.

So for the mobilenet float weights, get the weights as like in CIFAR10 implementation, like from huggingface or something, and then convert them to the same format as the current mobilenet params header. And PLEASE update the Readme files accordingly. If you want to create a new Readme file for the mobilenet float implementation, please do so. The same goes for the resnet50 implementation. Make sure to include instructions on how to run the new tests and any differences in expected outputs compared to the original implementations.