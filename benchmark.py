"""Compare the original and updated local runtimes, one engine at a time."""
import base64
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time

from check import normalized_words, send, start, stop, wait, word_errors


CASES = [
    ('short', 'Hello, this is a local dictation test. The microphone works and these words should appear in my text field.', ''),
    ('details', 'Please send Sarah the report on Friday. Book the meeting for ten thirty. Do not change the budget of two thousand dollars.', ''),
    ('negation', 'Do not approve the purchase. The amount is fifteen dollars, not fifty dollars.', ''),
    ('correction', 'Schedule the delivery for Tuesday, sorry, make that Thursday. Send it to Mira, not David.', ''),
    ('technical', 'Open the PostgreSQL database, review the Prisma migration, and deploy the NestJS service.', ''),
    ('vocabulary', 'Ask Nivara to open Murmur and check the PostgreSQL database.', 'Nivara, Murmur, PostgreSQL.'),
    ('long', 'Please send Sarah the report on Friday and review the three attachments before the meeting. '
     'The budget is two thousand dollars and the appointment starts at ten thirty in the morning. '
     'After lunch, call David about the delivery and ask whether the warehouse has received the equipment. '
     'We also need to charge the laptop, print the agenda, and confirm the room booking with reception. '
     'On Monday, prepare a summary of the open tasks and share it with the project team. '
     'Finally, remember to bring the access card and leave enough time to catch the train home.', ''),
]


def main():
    audio = []
    with tempfile.TemporaryDirectory(prefix='murmur-benchmark-') as directory:
        path = Path(directory) / 'speech.aiff'
        for name, text, _ in CASES:
            subprocess.run(['/usr/bin/say', '-v', 'Samantha', '-r', '140' if name == 'long' else '175',
                            '-o', str(path), text], check=True)
            audio.append(subprocess.run(['/opt/homebrew/bin/ffmpeg', '-v', 'error', '-i', str(path),
                                         '-f', 'f32le', '-ar', '16000', '-ac', '1', '-'],
                                        capture_output=True, check=True).stdout)
    report = {}
    whisper_script = Path(shutil.which('whisper') or '/opt/homebrew/bin/whisper')
    previous_python = whisper_script.read_text().splitlines()[0].removeprefix('#!')
    for engine, python in [('previous-runtime', previous_python), ('updated-runtime', sys.executable)]:
        worker = start('worker.py', python=python)
        rows = []
        try:
            ready = wait(worker, 'ready')
            assert ready['engine'] == 'Whisper', ready
            for index, ((name, expected, vocabulary), pcm) in enumerate(zip(CASES, audio)):
                timings = []
                for repeat in range(2):
                    send(worker, {'id': f'{name}-{repeat}', 'sequence': index,
                                  'audio': base64.b64encode(pcm).decode(), 'vocabulary': vocabulary})
                    result = wait(worker, 'result')
                    timings.append(result['seconds'])
                expected_words = normalized_words(expected)
                rows.append({'name': name, 'expected': expected, 'actual': result['text'],
                             'word_errors': word_errors(expected_words, normalized_words(result['text'])),
                             'words': len(expected_words), 'seconds': timings})
            # Exercise cancellation inside real inference, followed by a fresh successful job.
            long_pcm = audio[-1] * 3
            send(worker, {'id': 'cancel-asr', 'sequence': 1, 'audio': base64.b64encode(long_pcm).decode()})
            time.sleep(0.2)
            send(worker, {'type': 'cancel', 'id': 'cancel-asr'})
            assert wait(worker, 'cancelled')['id'] == 'cancel-asr'
            send(worker, {'id': 'after-cancel', 'sequence': 2, 'audio': base64.b64encode(audio[0]).decode()})
            recovered = wait(worker, 'result')
            assert normalized_words(recovered['text']) == normalized_words(CASES[0][1]), recovered
            report[engine] = {'ready': ready, 'cases': rows, 'cancellation_recovery': True}
        finally:
            stop(worker)
    baseline, candidate = report['previous-runtime']['cases'], report['updated-runtime']['cases']
    assert sum(r['word_errors'] for r in candidate) <= sum(r['word_errors'] for r in baseline), report
    for old, new in zip(baseline, candidate):
        assert new['word_errors'] <= old['word_errors'], (old, new)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
