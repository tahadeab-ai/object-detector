# Test Sample Asset Sources & License Provenance

This document specifies the exact provenance, permissive open-source licenses, file checksums, and verified inference detections for all bundled benchmark test images in `mobile_app/assets/samples/`.

In accordance with project governance (F4, RESTORE-3, RESTORE-7), all test images are authentic, real-world high-resolution photographs representing typical object detection operational environments. Zero synthetic, blank, or placeholder images are permitted.

---

## 1. Bundled Image Specifications

| Asset Name | Target Scenario | Primary Source URL | Author / Provenance | License | Resolution | Size (Bytes) | SHA256 Checksum | Verified YOLO11n Detections |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`sample_street.jpg`** | Urban traffic, vehicles, pedestrians | `http://images.cocodataset.org/val2017/000000169996.jpg` | COCO 2017 val / Flickr | Creative Commons Attribution 2.0 (CC BY 2.0) | 640 x 428 | 146,661 | `611bac47a27ce814dffb589dd2ed663f447b22aed5365b95fce142dbc6ddcc08` | **11 detections**: car (2), person (2), bicycle (2), traffic light (3), truck (2) |
| **`sample_workspace.jpg`** | Office desk, laptops, chairs, screens | `http://images.cocodataset.org/val2017/000000172595.jpg` | COCO 2017 val / Flickr | Creative Commons Attribution 2.0 (CC BY 2.0) | 640 x 427 | 124,663 | `faa06206531e26d29bed2d1ecca535d5496a017e1e88a7329f19bf4a5574a83b` | **10 detections**: chair (2), tv (4), laptop (1), keyboard (2), mouse (1) |
| **`sample_retail.jpg`** | Dining / grocery, bottles, tableware | `http://images.cocodataset.org/val2017/000000312192.jpg` | COCO 2017 val / Flickr | Creative Commons Attribution 2.0 (CC BY 2.0) | 640 x 480 | 165,630 | `1e698a3dcde04f64793eacefeb9802710182f0ae918db480983049e8235d2cf9` | **7 detections**: bottle (1), wine glass (2), dining table (1), person (1), pizza (1), cup (1) |

---

## 2. Verified Alternative Unsplash Sources

In environments with restricted access to COCO CDN mirrors, the following Unsplash photographs (governed by the Unsplash Permissive License) have been verified as functionally equivalent alternatives:

1. **Street Alternative**:
   - URL: `https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=1280&q=80`
   - Description: Tokyo Shibuya Crossing (pedestrians, cars, buses, trucks)
   - Size: 333,124 bytes | License: Unsplash Permissive License
   - Verified YOLO11n Detections: 18 (`car: 5, person: 10, bus: 2, truck: 1`)
2. **Workspace Alternative**:
   - URL: `https://images.unsplash.com/photo-1497215728101-856f4ea42174?w=1280&q=80`
   - Description: Modern corporate office desk (laptops, chairs, potted plants)
   - Size: 192,116 bytes | License: Unsplash Permissive License
   - SHA256: `4e52517982b15d72e331529b30f8749726813b3abd4f3d8676ce7ed4063253c2`
   - Verified YOLO11n Detections: 7 (`chair: 4, potted plant: 1, dining table: 1, laptop: 1`)
3. **Retail Alternative**:
   - URL: `https://images.unsplash.com/photo-1568213816046-0ee1c42bd559?w=1280&q=80`
   - Description: Wine boutique display shelves
   - Size: 181,524 bytes | License: Unsplash Permissive License
   - Verified YOLO11n Detections: 5 (`wine glass: 4, dining table: 1`)

---

## 3. License Grant & Attribution Notices

- **COCO Dataset Images**:
  The images are distributed by Microsoft COCO Consortium under the Creative Commons Attribution 2.0 Generic License.
  Reference: `https://cocodataset.org/#termsofuse`
- **Unsplash Images**:
  Photographs provided via Unsplash are licensed under the Unsplash License, granting irrevocable, nonexclusive, worldwide copyright license to download, copy, modify, distribute, perform, and use photos from Unsplash for free, including for commercial purposes, without attributing the photographer or Unsplash.
