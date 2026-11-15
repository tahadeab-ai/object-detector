# Third-Party Licenses

This project incorporates, links against, or utilizes several open-source libraries, models, and assets. Their respective licenses and copyright notices are reproduced below.

---

## 1. Ultralytics YOLO11

- **Component**: YOLO11 Neural Network Architecture & Model Weights (`yolo11n.pt`)
- **Copyright**: Copyright (c) 2023-2026 Ultralytics Inc.
- **License**: GNU Affero General Public License v3.0 (AGPL-3.0)
- **Source**: https://github.com/ultralytics/ultralytics

This software and its exported neural network weights are governed by the GNU Affero General Public License v3.0. A copy of the AGPL-3.0 license is included in the project root `LICENSE` file.

---

## 2. Tencent NCNN

- **Component**: Tencent NCNN Inference Engine & Vulkan Acceleration (`libncnn.a`, headers)
- **Copyright**: Copyright (c) 2017-2026 Tencent Inc. All rights reserved.
- **License**: BSD 3-Clause "New" or "Revised" License
- **Source**: https://github.com/Tencent/ncnn

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

## 3. Tencent PNNX (PyTorch Neural Network Exchange)

- **Component**: PNNX Model Optimizer & Graph Generator
- **Copyright**: Copyright (c) 2021-2026 Tencent Inc. All rights reserved.
- **License**: BSD 3-Clause "New" or "Revised" License
- **Source**: https://github.com/pnnx/pnnx

(Licensed under the BSD 3-Clause License as detailed in Section 2 above).

---

## 4. COCO Dataset Class Hierarchy & Evaluation Annotations

- **Component**: 80 COCO Object Class Labels (English & Arabic translation mapping)
- **Copyright**: Copyright (c) 2014-2026 COCO Consortium
- **License**: Creative Commons Attribution 4.0 International (CC BY 4.0)
- **Source**: https://cocodataset.org

You are free to share and adapt the material for any purpose, provided appropriate credit is given.

---

## 5. Sample Test Photographs (`mobile_app/assets/samples/`)

All sample images bundled for offline benchmarking are permissively licensed:

1. **`sample_street.jpg`**:
   - Scene: Urban street with vehicles, pedestrians, and traffic lights.
   - License: CC0 / Unsplash Permissive License (Free commercial & non-commercial use).
   - Provenance documented with SHA256 in `docs/assets_sources.md`.
2. **`sample_workspace.jpg`**:
   - Scene: Indoor office with laptops, chairs, cups, and desk electronics.
   - License: CC0 / Unsplash Permissive License.
   - Provenance documented with SHA256 in `docs/assets_sources.md`.
3. **`sample_retail.jpg`**:
   - Scene: Store retail shelves with bottles, groceries, and persons.
   - License: CC0 / Unsplash Permissive License.
   - Provenance documented with SHA256 in `docs/assets_sources.md`.

---

## 6. Rust Crates & Runtime Dependencies

- **`yolo_core` & `yolo_ffi` dependencies**:
  - Licensed under MIT or Apache-2.0.
  - Zero proprietary or non-distributable binary dependencies.

---

## 7. Flutter & Dart Packages

- Flutter SDK: BSD 3-Clause License (Copyright (c) 2014 The Flutter Authors).
- Selected pub dependencies: MIT or BSD-3-Clause licenses.

---

## 8. Go Fiber & Redis Dependencies

- **Go Standard Library**: BSD 3-Clause License (The Go Authors).
- **Fiber Web Framework**: MIT License (Copyright (c) 2019-2026 Fiber Authors).
- **go-redis**: BSD 2-Clause License (Copyright (c) 2013 The go-redis Authors).
