"""Offline Whisper worker. Audio and results travel over the app's private pipes."""
import base64
import json
import os
from pathlib import Path
import sys
import time

from jobs import Cancelled, Jobs

os.environ.setdefault("OMP_NUM_THREADS", "4")
import numpy as np


def emit(**message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


def load_transcriber():
    import torch
    import whisper

    checkpoint = Path.home() / ".cache/whisper/large-v3-turbo.pt"
    if not checkpoint.is_file():
        raise RuntimeError("Cached large-v3-turbo.pt is missing. Restore the cached model first.")
    torch.set_num_threads(4)
    # A file path bypasses Whisper's download code entirely.
    model = whisper.load_model(str(checkpoint), device="cpu")
    device = "cpu"
    if torch.backends.mps.is_available():
        # MPS cannot transfer Whisper's sparse alignment buffer; timestamps aren't used.
        model.alignment_heads = model.alignment_heads.to_dense()
        model = model.to("mps")
        device = "mps"
    def transcribe(audio, language='en', vocabulary=''):
        with torch.inference_mode():
            return model.transcribe(
                audio, language=language, fp16=False, temperature=0, beam_size=1, best_of=1,
                condition_on_previous_text=False, without_timestamps=len(audio) <= 16000 * 30,
                initial_prompt=vocabulary or None, verbose=None)

    transcribe(np.zeros(16000, dtype=np.float32))
    return transcribe, device, 'Whisper'


def main():
    started = time.monotonic()
    transcribe, device, engine = load_transcriber()
    jobs = Jobs()
    emit(type="ready", device=device, engine=engine, load_seconds=round(time.monotonic() - started, 2))
    for line in jobs:
        job = {}
        try:
            job = json.loads(line)
            if not isinstance(job, dict) or not isinstance(job.get("id"), str):
                raise ValueError("Invalid transcription job")
            vocabulary = job.get('vocabulary', '')
            if not isinstance(vocabulary, str) or len(vocabulary) > 500:
                raise ValueError('Names and terms must be at most 500 characters')
            raw = base64.b64decode(job["audio"], validate=True)
            if len(raw) % 4 or len(raw) > 16000 * 4 * 181:
                raise ValueError("Audio must be at most three minutes of 16 kHz float32 PCM")
            audio = np.frombuffer(raw, dtype="<f4").copy()
            if not np.isfinite(audio).all():
                raise ValueError("Audio contains invalid samples")
            started = time.monotonic()
            text = ""
            with jobs.processing(job['id']):
                if len(audio) >= 1600 and np.sqrt(np.mean(audio * audio)) > 0.0002:
                    result = transcribe(audio, job.get('language') or 'en', vocabulary)
                    text = " ".join(result["text"].split())
            emit(type="result", id=job["id"], sequence=job.get("sequence", 0),
                 text=text, seconds=round(time.monotonic() - started, 2))
        except Cancelled:
            emit(type='cancelled', id=job['id'])
        except Exception as error:
            emit(type="error", id=job.get("id", "") if isinstance(job, dict) else "",
                 sequence=job.get("sequence", 0) if isinstance(job, dict) else 0, message=str(error))
        finally:
            if isinstance(job, dict):
                jobs.discard(job.get('id'))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        emit(type="fatal", message=str(error))
        sys.exit(1)
