# Download Data Sample

These scripts use `rclone` to preview or download the dataset.

## Which Script To Use

| User / region | macOS or Linux | Windows |
|---|---|---|
| Mainland China / Tencent COS | `download_data_sample_tencent` | `download_data_sample_tencent.ps1` |
| Overseas / AWS S3 | `download_data_sample_aws` | `download_data_sample_aws.ps1` |

At startup, each script asks:

```text
Download the smaller sample with scene/task_category L2 directory structure?
```

Choose `y` for the smaller sample. Press Enter or choose `n` for the full dataset.

## Data Sources

Tencent COS:

- Full dataset: `client-data-sample-plain-1302052962`
- Smaller sample: `smaller-sample-1302052962`
- Region: `ap-beijing`

AWS S3:

- Full dataset: `s3://digients-recordings-sg/uploads/client-data-sample-plain/`
- Smaller sample: `s3://digients-recordings-sg/uploads/smaller-sample/`
- Region: `ap-southeast-1`

## Install rclone

Install `rclone` first:

```bash
# macOS
brew install rclone

# Ubuntu/Debian
sudo apt-get install rclone
```

Windows:

```powershell
winget install Rclone.Rclone
```

Official install docs: <https://rclone.org/install/>

## macOS / Linux Usage

You can run the bash scripts without changing permissions:

```bash
bash download_data_sample_tencent
bash download_data_sample_aws
```

If you prefer `./script_name`, add execute permission:

```bash
chmod +x download_data_sample_tencent download_data_sample_aws
./download_data_sample_tencent
./download_data_sample_aws
```

Do not use `chmod 777`; `chmod +x` is enough.

## Windows Usage

Run from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\download_data_sample_tencent.ps1
powershell -ExecutionPolicy Bypass -File .\download_data_sample_aws.ps1
```

## Credentials

Tencent scripts ask for:

- Tencent Cloud `SecretId`
- Tencent Cloud `SecretKey`

You can also set:

```bash
export COS_SECRET_ID=...
export COS_SECRET_KEY=...
```

AWS scripts ask for:

- AWS Access Key ID
- AWS Secret Access Key

You can also set:

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

AWS IAM username/password cannot be used by `rclone`; use an access key.

## Download Behavior

- Preview mode only lists dataset information.
- Download mode preserves the remote directory structure locally.
- Re-running a download resumes/skips files that are already complete.
- Press `Ctrl+C` to stop the active `rclone` download.
