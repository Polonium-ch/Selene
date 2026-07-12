import os
import urllib.request
import zipfile
import shutil

ORGANIZATION = "moonlight-stream"
PREBUILT_REPO = "moonlight-qt-deps"
TAG = "v8"
ASSET_NAME = "macos-universal.zip"

def download_and_extract():
    target_dir = os.path.join(os.getcwd(), "libs", "mac")
    url = f"https://github.com/{ORGANIZATION}/{PREBUILT_REPO}/releases/download/{TAG}/{ASSET_NAME}"

    if os.path.exists(target_dir):
        print("Cleaning target directory...")
        shutil.rmtree(target_dir)

    os.makedirs(target_dir, exist_ok=True)

    archive_path = os.path.join(target_dir, ASSET_NAME)

    print(f"Downloading {ASSET_NAME}...")
    try:
        urllib.request.urlretrieve(url, archive_path)
    except Exception as e:
        print(f"Download failed: {e}")
        exit(1)

    print(f"Extracting {ASSET_NAME}...")
    with zipfile.ZipFile(archive_path, 'r') as zip_ref:
        zip_ref.extractall(target_dir)

    os.remove(archive_path)
    print(f"Dependencies successfully deployed")

if __name__ == "__main__":
    download_and_extract()
