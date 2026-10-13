import array, pathlib, sys, wave
root=pathlib.Path(sys.argv[1]); files=list(root.glob('*.wav'))
assert len(files)==31, len(files)
for file in files:
    with wave.open(str(file),'rb') as f:
        assert f.getnchannels()==1 and f.getsampwidth()==2 and f.getframerate()==22050
        pcm=array.array('h',f.readframes(f.getnframes()))
        if sys.byteorder!='little': pcm.byteswap()
        peak=max(abs(x) for x in pcm)
        assert 50 < peak <= 26215, (file,peak)
        if file.stem.startswith('ambient'):
            assert abs(pcm[-1]-pcm[0]) < 6000, 'ambient seam discontinuity'
        else:
            assert pcm[0]==0 and pcm[-1]==0, 'one-shot endpoint click'
print('PASS: WAV formats, non-silence, headroom, and loop seam')
