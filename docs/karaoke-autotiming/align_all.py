import json, sys, soundfile as sf, time
from align_mms import run_scene, SR
gold=json.load(open('gold/gold_all.json')); pred={}; t0=time.time()
for sid,ts in gold.items():
    slug=sid.replace('/','__'); wave,sr=sf.read(f'audio_all/{slug}.wav',dtype='float32'); assert sr==SR
    if wave.ndim>1: wave=wave.mean(axis=1)
    try:
        pred[sid]=run_scene(wave, ts['lines'], 'whole')
        print(sid, 'ok', round(time.time()-t0,1), flush=True)
    except Exception as e:
        print(sid, 'FAIL', repr(e)[:200], flush=True)
json.dump(pred, open('pred_all_whole.json','w'), ensure_ascii=False)
print('total seconds', round(time.time()-t0,1))
