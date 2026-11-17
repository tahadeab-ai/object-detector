import os
import urllib.request
import hashlib

models = [
    ("yolo11n.ncnn.param", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n.ncnn.param"),
    ("yolo11n.ncnn.bin", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n.ncnn.bin"),
    ("yolo11n_seg.ncnn.param", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_seg.ncnn.param"),
    ("yolo11n_seg.ncnn.bin", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_seg.ncnn.bin"),
    ("yolo11n_pose.ncnn.param", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_pose.ncnn.param"),
    ("yolo11n_pose.ncnn.bin", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_pose.ncnn.bin"),
    ("yolo11n_cls.ncnn.param", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_cls.ncnn.param"),
    ("yolo11n_cls.ncnn.bin", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_cls.ncnn.bin"),
    ("yolo11n_obb.ncnn.param", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_obb.ncnn.param"),
    ("yolo11n_obb.ncnn.bin", "https://raw.githubusercontent.com/nihui/ncnn-android-yolo11/master/app/src/main/assets/yolo11n_obb.ncnn.bin"),
]

out_dir = os.path.join("mobile_app", "assets", "models")
os.makedirs(out_dir, exist_ok=True)

headers = {"User-Agent": "AntigravityAgent"}

for name, url in models:
    dest = os.path.join(out_dir, name)
    if os.path.exists(dest) and os.path.getsize(dest) > 1000:
        print(f"Already exists: {name} ({os.path.getsize(dest)} bytes)")
        continue
    print(f"Downloading {name} from {url}...")
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp, open(dest, "wb") as f:
        data = resp.read()
        f.write(data)
    h = hashlib.sha256(open(dest, "rb").read()).hexdigest()
    print(f"Downloaded {name}: {len(data)} bytes, sha256={h[:16]}...")
