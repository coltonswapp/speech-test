"""Modal deployment of the aligner.

    modal deploy modal_app.py          # → https://<workspace>--shizen-aligner-web.modal.run
    modal serve modal_app.py           # hot-reloading dev URL

Secret: create once with `modal secret create shizen-aligner ALIGNER_TOKEN=<random>`.
Set the same value as ALIGNER_TOKEN in Vercel, and the printed URL as ALIGNER_URL.
"""
import modal

APP_NAME = "shizen-aligner"
TORCH_VERSION = "2.5.1"
# None = CPU (8 vCPU). Set to "T4" if CPU cannot hold the 5 s warm bar; the
# image then pulls CUDA wheels and core.py picks the device automatically.
GPU = None


def _download_model() -> None:
    import torchaudio

    torchaudio.pipelines.MMS_FA.get_model(with_star=False)


image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libsndfile1")
    .pip_install(
        f"torch=={TORCH_VERSION}",
        f"torchaudio=={TORCH_VERSION}",
        index_url="https://download.pytorch.org/whl/cu121" if GPU else "https://download.pytorch.org/whl/cpu",
    )
    .pip_install(
        "fastapi>=0.115",
        "httpx>=0.27",
        "numpy<2.3",
        "pykakasi>=2.3",
        "soundfile>=0.12",
        "pydantic>=2.7",
    )
    .env({"TORCH_HOME": "/root/.cache/torch", "OMP_NUM_THREADS": "8", "ALIGNER_THREADS": "8"})
    .run_function(_download_model)
    .add_local_python_source("aligner")
)

app = modal.App(APP_NAME)


@app.function(
    image=image,
    # MMS_FA on CPU scales near-linearly with threads; 4 vCPU landed at ~9 s
    # per 40 s take, 8 brings it under the 5 s bar. Cost per request is flat.
    cpu=8.0,
    memory=6144,
    gpu=GPU,
    secrets=[modal.Secret.from_name("shizen-aligner")],
    scaledown_window=300,
    timeout=120,
)
@modal.concurrent(max_inputs=2)
@modal.asgi_app()
def web():
    from aligner.app import app as fastapi_app, warm

    warm()
    return fastapi_app
